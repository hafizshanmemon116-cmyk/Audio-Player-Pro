require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.content.*"
import "android.media.*"
import "android.media.audiofx.*"
import "android.provider.*"
import "android.net.*"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.lang.Math"

local ctx = activity or service or this
if not ctx then
  local ActivityThread = luajava.bindClass("android.app.ActivityThread")
  ctx = ActivityThread.currentApplication().getApplicationContext()
end

local mainHandler = Handler(Looper.getMainLooper())
local prefs = ctx.getSharedPreferences("MediaPlayerProPrefs", Context.MODE_PRIVATE)

local skipDuration = prefs.getInt("skipDuration", 10000)
local backgroundPlay = prefs.getBoolean("backgroundPlay", false)
local singleLoop = prefs.getBoolean("singleLoop", false)
local playbackSpeed = prefs.getFloat("playbackSpeed", 1.0)
local lastPlayingPath = prefs.getString("lastPlayingPath", "")

local function getHiddenList(key)
  local str = prefs.getString(key, "")
  local t = {}
  if str ~= "" then
    for item in string.gmatch(str, "[^|]+") do
      t[item] = true
    end
  end
  return t
end

local function saveHiddenList(key, tbl)
  local list = {}
  for item, _ in pairs(tbl) do
    table.insert(list, item)
  end
  prefs.edit().putString(key, table.concat(list, "|")).apply()
end

local hiddenFiles = getHiddenList("hiddenFiles")
local hiddenFolders = getHiddenList("hiddenFolders")
local favoriteFiles = getHiddenList("favoriteFiles")

if not _G.GlobalMediaPlayer then
  _G.GlobalMediaPlayer = MediaPlayer()
end
local mediaPlayer = _G.GlobalMediaPlayer

local mediaList = {}
local folderList = {}
local activeList = {}
local currentIndex = -1
local isPlaying = false

pcall(function()
  isPlaying = mediaPlayer.isPlaying()
end)

local abLoopStart = -1
local abLoopEnd = -1
local isABLoopActive = false

local function isVideoFile(fileName)
  if not fileName then return false end
  local ext = fileName:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    if ext == "mp4" or ext == "mkv" or ext == "webm" or ext == "3gp" or ext == "avi" or ext == "flv" or ext == "mov" then
      return true
    end
  end
  return false
end

local function isAudioFile(fileName)
  if not fileName then return false end
  local ext = fileName:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    if ext == "mp3" or ext == "m4a" or ext == "wav" or ext == "aac" or ext == "ogg" or ext == "flac" or ext == "opus" or ext == "amr" then
      return true
    end
  end
  return false
end

local function isMediaFile(fileName)
  return isVideoFile(fileName) or isAudioFile(fileName)
end

local function showSafeDialog(builder)
  local dlg
  if builder.create then
    dlg = builder.create()
  else
    dlg = builder
  end
  if not activity then
    pcall(function()
      local winType = WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
      if Build.VERSION.SDK_INT >= 26 then
        winType = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
      end
      dlg.getWindow().setType(winType)
    end)
  end
  dlg.show()
  return dlg
end

local function formatDuration(ms)
  if not ms or ms <= 0 then return "00:00" end
  local totalSeconds = math.floor(ms / 1000)
  local minutes = math.floor(totalSeconds / 60)
  local seconds = totalSeconds % 60
  return string.format("%02d:%02d", minutes, seconds)
end

local function formatSize(bytes)
  if not bytes then return "0 KB" end
  local kb = bytes / 1024
  if kb >= 1024 then
    return string.format("%.2f MB", kb / 1024)
  else
    return string.format("%.2f KB", kb)
  end
end

local function getSkipSecondsText()
  local secs = math.floor(skipDuration / 1000)
  return tostring(secs) .. "s"
end

local function copyFileRaw(srcFile, destFile)
  local input = FileInputStream(srcFile)
  local output = FileOutputStream(destFile)
  local buffer = luajava.newArray(Byte.TYPE, 4096)
  local bytesRead = input.read(buffer)
  while bytesRead > 0 do
    output.write(buffer, 0, bytesRead)
    bytesRead = input.read(buffer)
  end
  input.close()
  output.close()
end

local function copyDirectoryRaw(srcDir, destDir)
  if not destDir.exists() then
    destDir.mkdirs()
  end
  local files = srcDir.listFiles()
  if files then
    for i = 0, #files - 1 do
      local f = files[i]
      local target = File(destDir, f.getName())
      if f.isDirectory() then
        copyDirectoryRaw(f, target)
      else
        copyFileRaw(f, target)
      end
    end
  end
end

local function deleteDirectoryRaw(f)
  if f.isDirectory() then
    local files = f.listFiles()
    if files then
      for i = 0, #files - 1 do
        deleteDirectoryRaw(files[i])
      end
    end
  end
  f.delete()
end

local function applyPlaybackSpeed()
  if Build.VERSION.SDK_INT >= 23 and mediaPlayer then
    pcall(function()
      local PlaybackParamsClass = luajava.bindClass("android.media.PlaybackParams")
      local params = mediaPlayer.getPlaybackParams()
      if not params then
        params = PlaybackParamsClass()
      end
      params.setSpeed(playbackSpeed)
      local wasPlaying = mediaPlayer.isPlaying()
      mediaPlayer.setPlaybackParams(params)
      if not wasPlaying then
        mediaPlayer.pause()
      end
    end)
  end
end

local openExplorerDialog
local openDedicatedVideoPlayer
local playMediaAtIndex
local showPlayerDialog
local showOperationDialog

local mainLayout = LinearLayout(ctx)
mainLayout.setOrientation(LinearLayout.VERTICAL)
mainLayout.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT))
mainLayout.setPadding(16, 16, 16, 16)

local titleView = TextView(ctx)
titleView.setText("Media Player Pro")
titleView.setTextSize(22)
titleView.setTextColor(0xFF1E88E5)
titleView.setGravity(Gravity.CENTER)
mainLayout.addView(titleView)

local devView = TextView(ctx)
devView.setText("Developer: Jahanzaib")
devView.setTextSize(14)
devView.setGravity(Gravity.CENTER)
devView.setPadding(0, 0, 0, 15)
mainLayout.addView(devView)

local btnAudioPlayer = Button(ctx)
btnAudioPlayer.setText("Audio Player")
btnAudioPlayer.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
mainLayout.addView(btnAudioPlayer)

local btnVideoPlayerMain = Button(ctx)
btnVideoPlayerMain.setText("Video Player")
btnVideoPlayerMain.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
mainLayout.addView(btnVideoPlayerMain)

local bottomLayout = LinearLayout(ctx)
bottomLayout.setOrientation(LinearLayout.VERTICAL)
bottomLayout.setGravity(Gravity.CENTER)
bottomLayout.setPadding(0, 20, 0, 0)

local btnSettings = Button(ctx)
btnSettings.setText("Settings")
btnSettings.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
bottomLayout.addView(btnSettings)

local btnAboutSupportMain = Button(ctx)
btnAboutSupportMain.setText("About & Support")
btnAboutSupportMain.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
bottomLayout.addView(btnAboutSupportMain)

local btnExit = Button(ctx)
btnExit.setText("Exit")
btnExit.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
bottomLayout.addView(btnExit)

mainLayout.addView(bottomLayout)

local mainDialog = nil
if activity then
  activity.setContentView(mainLayout)
else
  local mainBuilder = AlertDialog.Builder(ctx)
  mainBuilder.setView(mainLayout)
  mainDialog = showSafeDialog(mainBuilder)
end

local function showAudioPlayerMenu()
  local audioLayout = LinearLayout(ctx)
  audioLayout.setOrientation(LinearLayout.VERTICAL)
  audioLayout.setPadding(20, 20, 20, 20)

  local btnAudioFiles = Button(ctx)
  btnAudioFiles.setText("All Audio Files")
  btnAudioFiles.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  audioLayout.addView(btnAudioFiles)

  local btnAudioFolders = Button(ctx)
  btnAudioFolders.setText("Audio Folders")
  btnAudioFolders.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  audioLayout.addView(btnAudioFolders)

  local builder = AlertDialog.Builder(ctx)
  builder.setTitle("Audio Player")
  builder.setView(audioLayout)
  builder.setPositiveButton("Go Back", nil)

  local audioMenuDlg = showSafeDialog(builder)

  btnAudioFiles.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      audioMenuDlg.dismiss()
      openExplorerDialog(false, nil, false, false, "audio")
    end
  })

  btnAudioFolders.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      audioMenuDlg.dismiss()
      openExplorerDialog(true, nil, false, false, "audio")
    end
  })
end

local function showVideoPlayerMenu()
  local videoLayout = LinearLayout(ctx)
  videoLayout.setOrientation(LinearLayout.VERTICAL)
  videoLayout.setPadding(20, 20, 20, 20)

  local btnVideoFiles = Button(ctx)
  btnVideoFiles.setText("All Video Files")
  btnVideoFiles.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  videoLayout.addView(btnVideoFiles)

  local btnVideoFolders = Button(ctx)
  btnVideoFolders.setText("Video Folders")
  btnVideoFolders.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  videoLayout.addView(btnVideoFolders)

  local builder = AlertDialog.Builder(ctx)
  builder.setTitle("Video Player")
  builder.setView(videoLayout)
  builder.setPositiveButton("Go Back", nil)

  local videoMenuDlg = showSafeDialog(builder)

  btnVideoFiles.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      videoMenuDlg.dismiss()
      openExplorerDialog(false, nil, false, false, "video")
    end
  })

  btnVideoFolders.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      videoMenuDlg.dismiss()
      openExplorerDialog(true, nil, false, false, "video")
    end
  })
end

btnAudioPlayer.setOnClickListener(View.OnClickListener{
  onClick = function(v)
    showAudioPlayerMenu()
  end
})

btnVideoPlayerMain.setOnClickListener(View.OnClickListener{
  onClick = function(v)
    showVideoPlayerMenu()
  end
})

local playerDialog = nil
local trackStatusView = nil
local seekBar = nil
local timeCurrent = nil
local timeTotal = nil
local btnPlayPause = nil
local lyricsView = nil

local function showPlayerDialog()
  if playerDialog then return end

  local scrollView = ScrollView(ctx)
  local layout = LinearLayout(ctx)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(20, 20, 20, 20)
  scrollView.addView(layout)

  trackStatusView = TextView(ctx)
  trackStatusView.setText("No Media Playing")
  trackStatusView.setTextSize(16)
  trackStatusView.setGravity(Gravity.CENTER)
  trackStatusView.setPadding(0, 8, 0, 8)
  layout.addView(trackStatusView)

  local seekBarLayout = LinearLayout(ctx)
  seekBarLayout.setOrientation(LinearLayout.HORIZONTAL)

  timeCurrent = TextView(ctx)
  timeCurrent.setText("00:00")
  seekBarLayout.addView(timeCurrent)

  seekBar = SeekBar(ctx)
  seekBar.setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1))
  seekBarLayout.addView(seekBar)

  timeTotal = TextView(ctx)
  timeTotal.setText("00:00")
  seekBarLayout.addView(timeTotal)

  layout.addView(seekBarLayout)

  local controlsLayout = LinearLayout(ctx)
  controlsLayout.setOrientation(LinearLayout.HORIZONTAL)
  controlsLayout.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  controlsLayout.setGravity(Gravity.CENTER)

  local function createControlButton(text)
    local btn = Button(ctx)
    btn.setText(text)
    btn.setTextSize(10)
    btn.setPadding(4, 8, 4, 8)
    local params = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
    params.setMargins(2, 2, 2, 2)
    btn.setLayoutParams(params)
    return btn
  end

  local btnPrev = createControlButton("Prev")
  controlsLayout.addView(btnPrev)

  local btnRewind = createControlButton("- " .. getSkipSecondsText())
  controlsLayout.addView(btnRewind)

  btnPlayPause = createControlButton(isPlaying and "Pause" or "Play")
  controlsLayout.addView(btnPlayPause)

  local btnForward = createControlButton("+ " .. getSkipSecondsText())
  controlsLayout.addView(btnForward)

  local btnNext = createControlButton("Next")
  controlsLayout.addView(btnNext)

  layout.addView(controlsLayout)

  local row2 = LinearLayout(ctx)
  row2.setOrientation(LinearLayout.HORIZONTAL)
  row2.setPadding(0, 10, 0, 10)

  local btnSpeed = createControlButton("Speed: " .. tostring(playbackSpeed) .. "x")
  row2.addView(btnSpeed)

  local btnABLoop = createControlButton("Set A-B Loop")
  row2.addView(btnABLoop)

  local btnFullscreen = createControlButton("Video Fullscreen")
  row2.addView(btnFullscreen)

  layout.addView(row2)

  local rowCopyMove = LinearLayout(ctx)
  rowCopyMove.setOrientation(LinearLayout.HORIZONTAL)
  rowCopyMove.setPadding(0, 5, 0, 5)

  local btnAudioCopy = createControlButton("Copy")
  rowCopyMove.addView(btnAudioCopy)

  local btnAudioMove = createControlButton("Move")
  rowCopyMove.addView(btnAudioMove)

  layout.addView(rowCopyMove)

  local row3 = LinearLayout(ctx)
  row3.setOrientation(LinearLayout.HORIZONTAL)

  local btnAddBookmark = createControlButton("Add Bookmark")
  row3.addView(btnAddBookmark)

  local btnViewBookmarks = createControlButton("View Bookmarks")
  row3.addView(btnViewBookmarks)

  local btnFavoriteToggle = createControlButton("Favorite")
  row3.addView(btnFavoriteToggle)

  layout.addView(row3)

  lyricsView = TextView(ctx)
  lyricsView.setText("Live Info Display")
  lyricsView.setTextSize(12)
  lyricsView.setGravity(Gravity.CENTER)
  lyricsView.setPadding(0, 15, 0, 15)
  lyricsView.setTextColor(0xFF757575)
  layout.addView(lyricsView)

  local builder = AlertDialog.Builder(ctx)
  builder.setTitle("Media Player Pro Controls")
  builder.setView(scrollView)
  builder.setPositiveButton("Go Back", DialogInterface.OnClickListener{
    onClick = function(d, w)
      playerDialog = nil
    end
  })

  playerDialog = showSafeDialog(builder)

  seekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{
    onProgressChanged = function(sb, progress, fromUser)
      if fromUser and mediaPlayer then
        pcall(function()
          mediaPlayer.seekTo(progress)
          timeCurrent.setText(formatDuration(progress))
        end)
      end
    end,
    onStartTrackingTouch = function(sb) end,
    onStopTrackingTouch = function(sb) end
  })

  btnPlayPause.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if not mediaPlayer then return end
      pcall(function()
        if mediaPlayer.isPlaying() then
          mediaPlayer.pause()
          isPlaying = false
          btnPlayPause.setText("Play")
        else
          if currentIndex == -1 and #activeList > 0 then
            playMediaAtIndex(1)
          else
            mediaPlayer.start()
            applyPlaybackSpeed()
            isPlaying = true
            btnPlayPause.setText("Pause")
          end
        end
      end)
    end
  })

  btnRewind.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      pcall(function()
        if mediaPlayer then
          local current = mediaPlayer.getCurrentPosition()
          local target = math.max(0, current - skipDuration)
          mediaPlayer.seekTo(target)
        end
      end)
    end
  })

  btnForward.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      pcall(function()
        if mediaPlayer then
          local current = mediaPlayer.getCurrentPosition()
          local duration = mediaPlayer.getDuration()
          local target = math.min(duration, current + skipDuration)
          mediaPlayer.seekTo(target)
        end
      end)
    end
  })

  btnPrev.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex > 1 then
        playMediaAtIndex(currentIndex - 1)
      end
    end
  })

  btnNext.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex < #activeList then
        playMediaAtIndex(currentIndex + 1)
      end
    end
  })

  btnSpeed.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      local speeds = {"0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x", "3.0x", "5.0x"}
      local speedVals = {0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0}
      local sBuilder = AlertDialog.Builder(ctx)
      sBuilder.setTitle("Playback Speed")
      sBuilder.setItems(speeds, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
          playbackSpeed = speedVals[which + 1]
          btnSpeed.setText("Speed: " .. speeds[which + 1])
          prefs.edit().putFloat("playbackSpeed", playbackSpeed).apply()
          applyPlaybackSpeed()
        end
      })
      showSafeDialog(sBuilder)
    end
  })

  btnABLoop.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if abLoopStart == -1 then
        abLoopStart = mediaPlayer.getCurrentPosition()
        btnABLoop.setText("A: " .. formatDuration(abLoopStart) .. " (Set B)")
        Toast.makeText(ctx, "A-Point Set", Toast.LENGTH_SHORT).show()
      elseif abLoopEnd == -1 then
        abLoopEnd = mediaPlayer.getCurrentPosition()
        if abLoopEnd > abLoopStart then
          isABLoopActive = true
          btnABLoop.setText("Looping A-B (Reset)")
          Toast.makeText(ctx, "A-B Loop Active", Toast.LENGTH_SHORT).show()
        else
          abLoopStart = -1
          abLoopEnd = -1
          btnABLoop.setText("Set A-B Loop")
          Toast.makeText(ctx, "Invalid B point", Toast.LENGTH_SHORT).show()
        end
      else
        abLoopStart = -1
        abLoopEnd = -1
        isABLoopActive = false
        btnABLoop.setText("Set A-B Loop")
        Toast.makeText(ctx, "A-B Loop Cleared", Toast.LENGTH_SHORT).show()
      end
    end
  })

  btnFullscreen.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        if isVideoFile(item.path) then
          openDedicatedVideoPlayer(item.path)
        else
          Toast.makeText(ctx, "Selected file is an audio track", Toast.LENGTH_SHORT).show()
        end
      end
    end
  })

  btnAudioCopy.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        showOperationDialog("copy", {{path = item.path, isFolder = false}}, nil, nil)
      end
    end
  })

  btnAudioMove.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        showOperationDialog("move", {{path = item.path, isFolder = false}}, nil, nil)
      end
    end
  })

  btnAddBookmark.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local currentPos = mediaPlayer.getCurrentPosition()
        local item = activeList[currentIndex]
        local bKey = "bm_" .. item.path
        local existing = prefs.getString(bKey, "")
        local newBookmark = formatDuration(currentPos) .. "|" .. existing
        prefs.edit().putString(bKey, newBookmark).apply()
        Toast.makeText(ctx, "Bookmark added at " .. formatDuration(currentPos), Toast.LENGTH_SHORT).show()
      end
    end
  })

  btnViewBookmarks.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        local bKey = "bm_" .. item.path
        local existing = prefs.getString(bKey, "")
        local bmList = {}
        for bm in string.gmatch(existing, "[^|]+") do
          table.insert(bmList, bm)
        end
        local bDlg = AlertDialog.Builder(ctx)
        bDlg.setTitle("Bookmarks & Notes")
        if #bmList == 0 then
          bDlg.setMessage("No bookmarks saved yet.")
        else
          bDlg.setItems(bmList, DialogInterface.OnClickListener{
            onClick = function(d, which)
            end
          })
        end
        bDlg.setPositiveButton("Go Back", nil)
        showSafeDialog(bDlg)
      end
    end
  })

  btnFavoriteToggle.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        if favoriteFiles[item.path] then
          favoriteFiles[item.path] = nil
          Toast.makeText(ctx, "Removed from Favorites", Toast.LENGTH_SHORT).show()
        else
          favoriteFiles[item.path] = true
          Toast.makeText(ctx, "Added to Favorites", Toast.LENGTH_SHORT).show()
        end
        saveHiddenList("favoriteFiles", favoriteFiles)
      end
    end
  })
end

playMediaAtIndex = function(index)
  if index < 1 or index > #activeList then return end
  currentIndex = index
  local item = activeList[currentIndex]

  pcall(function()
    mediaPlayer.reset()
    mediaPlayer.setDataSource(item.path)
    mediaPlayer.prepare()
    mediaPlayer.setLooping(singleLoop)
    mediaPlayer.start()
    applyPlaybackSpeed()
    isPlaying = true

    if isVideoFile(item.path) then
      openDedicatedVideoPlayer(item.path)
    else
      showPlayerDialog()
      if btnPlayPause then btnPlayPause.setText("Pause") end
      if trackStatusView then trackStatusView.setText("Playing: " .. item.name) end
      if seekBar then seekBar.setMax(mediaPlayer.getDuration()) end
      if timeTotal then timeTotal.setText(formatDuration(mediaPlayer.getDuration())) end
      if lyricsView then lyricsView.setText("Now Playing: " .. item.name) end
    end

    prefs.edit().putString("lastPlayingPath", item.path).apply()
  end)
end

openDedicatedVideoPlayer = function(videoPath)
  local vDialog = Dialog(ctx, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
  local playerRoot = LinearLayout(ctx)
  playerRoot.setOrientation(LinearLayout.VERTICAL)
  playerRoot.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT))
  playerRoot.setBackgroundColor(0xFF000000)

  local headerBar = LinearLayout(ctx)
  headerBar.setOrientation(LinearLayout.HORIZONTAL)
  headerBar.setGravity(Gravity.CENTER_VERTICAL)
  headerBar.setPadding(8, 8, 8, 8)
  headerBar.setBackgroundColor(0x88000000)

  local vTitle = TextView(ctx)
  vTitle.setTextColor(0xFFFFFFFF)
  vTitle.setTextSize(13)
  vTitle.setGravity(Gravity.CENTER_VERTICAL)
  vTitle.setPadding(8, 0, 8, 0)
  vTitle.setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0))
  headerBar.addView(vTitle)

  local lblSpeed = TextView(ctx)
  lblSpeed.setText("Speed: ")
  lblSpeed.setTextColor(0xFFFFFFFF)
  lblSpeed.setTextSize(12)
  headerBar.addView(lblSpeed)

  local speedCombo = Spinner(ctx)
  local speedOpts = {"0.5x", "1x", "1.5x", "2x", "3x", "5x", "10x"}
  local speedVals = {0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0}
  local speedComboAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, speedOpts)
  speedComboAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  speedCombo.setAdapter(speedComboAdapter)

  local initialComboIdx = 1
  for idx, spd in ipairs(speedVals) do
    if math.abs(spd - playbackSpeed) < 0.05 then
      initialComboIdx = idx - 1
      break
    end
  end
  speedCombo.setSelection(initialComboIdx)
  headerBar.addView(speedCombo)

  local btnVideoFav = Button(ctx)
  btnVideoFav.setText("Fav")
  btnVideoFav.setTextSize(10)
  headerBar.addView(btnVideoFav)

  local btnVideoCopy = Button(ctx)
  btnVideoCopy.setText("Copy")
  btnVideoCopy.setTextSize(10)
  headerBar.addView(btnVideoCopy)

  local btnVideoMove = Button(ctx)
  btnVideoMove.setText("Move")
  btnVideoMove.setTextSize(10)
  headerBar.addView(btnVideoMove)

  local btnGoBack = Button(ctx)
  btnGoBack.setText("Go Back")
  headerBar.addView(btnGoBack)

  playerRoot.addView(headerBar)

  local videoFrame = FrameLayout(ctx)
  local frameParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1.0)
  videoFrame.setLayoutParams(frameParams)

  local videoView = VideoView(ctx)
  local vvParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
  vvParams.gravity = Gravity.CENTER
  videoView.setLayoutParams(vvParams)
  videoFrame.addView(videoView)

  playerRoot.addView(videoFrame)

  local controlBox = LinearLayout(ctx)
  controlBox.setOrientation(LinearLayout.VERTICAL)
  controlBox.setBackgroundColor(0xAA000000)
  controlBox.setPadding(12, 8, 12, 12)

  local timeRow = LinearLayout(ctx)
  timeRow.setOrientation(LinearLayout.HORIZONTAL)
  timeRow.setGravity(Gravity.CENTER_VERTICAL)

  local vTimeCur = TextView(ctx)
  vTimeCur.setTextColor(0xFFFFFFFF)
  vTimeCur.setText("00:00")
  timeRow.addView(vTimeCur)

  local vSeekBar = SeekBar(ctx)
  vSeekBar.setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0))
  timeRow.addView(vSeekBar)

  local vTimeTot = TextView(ctx)
  vTimeTot.setTextColor(0xFFFFFFFF)
  vTimeTot.setText("00:00")
  timeRow.addView(vTimeTot)

  controlBox.addView(timeRow)

  local actionsRow = LinearLayout(ctx)
  actionsRow.setOrientation(LinearLayout.HORIZONTAL)
  actionsRow.setGravity(Gravity.CENTER)

  local function makeActionBtn(text)
    local b = Button(ctx)
    b.setText(text)
    b.setTextSize(10)
    b.setPadding(4, 4, 4, 4)
    local p = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
    p.setMargins(2, 0, 2, 0)
    b.setLayoutParams(p)
    return b
  end

  local btnVPrev = makeActionBtn("Previous Video")
  actionsRow.addView(btnVPrev)

  local btnVRewind = makeActionBtn("Rewind")
  actionsRow.addView(btnVRewind)

  local btnVPlayPause = makeActionBtn("Pause")
  actionsRow.addView(btnVPlayPause)

  local btnVFastForward = makeActionBtn("FastForward")
  actionsRow.addView(btnVFastForward)

  local btnVNext = makeActionBtn("Next Video")
  actionsRow.addView(btnVNext)

  controlBox.addView(actionsRow)
  playerRoot.addView(controlBox)

  vDialog.setContentView(playerRoot)

  local videoMediaController = nil
  local isVideoActive = true

  local function applyVVPlaybackSpeed(speedVal)
    playbackSpeed = speedVal
    prefs.edit().putFloat("playbackSpeed", playbackSpeed).apply()
    if Build.VERSION.SDK_INT >= 23 and videoMediaController then
      pcall(function()
        local PlaybackParamsClass = luajava.bindClass("android.media.PlaybackParams")
        local p = videoMediaController.getPlaybackParams()
        if not p then p = PlaybackParamsClass() end
        p.setSpeed(speedVal)
        videoMediaController.setPlaybackParams(p)
      end)
    end
  end

  local function startVideo(path)
    if not path or path == "" then return end
    pcall(function()
      if mediaPlayer and mediaPlayer.isPlaying() then
        mediaPlayer.pause()
        isPlaying = false
        if btnPlayPause then btnPlayPause.setText("Play") end
      end
    end)

    vTitle.setText(File(path).getName())
    videoView.setVideoPath(path)
    videoView.requestFocus()
    videoView.start()
    btnVPlayPause.setText("Pause")
    prefs.edit().putString("lastPlayingPath", path).apply()
  end

  videoView.setOnPreparedListener(MediaPlayer.OnPreparedListener{
    onPrepared = function(mp)
      videoMediaController = mp
      mp.setLooping(singleLoop)
      vSeekBar.setMax(videoView.getDuration())
      vTimeTot.setText(formatDuration(videoView.getDuration()))
      applyVVPlaybackSpeed(playbackSpeed)
    end
  })

  videoView.setOnCompletionListener(MediaPlayer.OnCompletionListener{
    onCompletion = function(mp)
      if singleLoop then
        videoView.seekTo(0)
        videoView.start()
      elseif currentIndex < #activeList and currentIndex > 0 then
        currentIndex = currentIndex + 1
        startVideo(activeList[currentIndex].path)
      else
        btnVPlayPause.setText("Play")
      end
    end
  })

  speedCombo.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
    onItemSelected = function(p, v, pos, id)
      applyVVPlaybackSpeed(speedVals[pos + 1])
    end,
    onNothingSelected = function(p) end
  })

  btnVideoFav.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        if favoriteFiles[item.path] then
          favoriteFiles[item.path] = nil
          Toast.makeText(ctx, "Removed from Favorites", Toast.LENGTH_SHORT).show()
        else
          favoriteFiles[item.path] = true
          Toast.makeText(ctx, "Added to Favorites", Toast.LENGTH_SHORT).show()
        end
        saveHiddenList("favoriteFiles", favoriteFiles)
      end
    end
  })

  btnVideoCopy.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        showOperationDialog("copy", {{path = item.path, isFolder = false}}, nil, nil)
      end
    end
  })

  btnVideoMove.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        showOperationDialog("move", {{path = item.path, isFolder = false}}, nil, nil)
      end
    end
  })

  local vHandler = Handler(Looper.getMainLooper())
  local vRunnable
  vRunnable = Runnable{
    run = function()
      pcall(function()
        if isVideoActive and videoView and videoView.isPlaying() then
          local cur = videoView.getCurrentPosition()
          local dur = videoView.getDuration()
          vSeekBar.setProgress(cur)
          vTimeCur.setText(formatDuration(cur))
          vSeekBar.setMax(dur)
          vTimeTot.setText(formatDuration(dur))
        end
      end)
      if isVideoActive then
        vHandler.postDelayed(vRunnable, 1000)
      end
    end
  }
  vHandler.postDelayed(vRunnable, 1000)

  vSeekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{
    onProgressChanged = function(sb, progress, fromUser)
      if fromUser and videoView then
        videoView.seekTo(progress)
        vTimeCur.setText(formatDuration(progress))
      end
    end,
    onStartTrackingTouch = function(sb) end,
    onStopTrackingTouch = function(sb) end
  })

  btnVPlayPause.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if videoView.isPlaying() then
        videoView.pause()
        btnVPlayPause.setText("Play")
      else
        videoView.start()
        btnVPlayPause.setText("Pause")
        applyVVPlaybackSpeed(playbackSpeed)
      end
    end
  })

  btnVRewind.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      local pos = math.max(0, videoView.getCurrentPosition() - skipDuration)
      videoView.seekTo(pos)
    end
  })

  btnVFastForward.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      local pos = math.min(videoView.getDuration(), videoView.getCurrentPosition() + skipDuration)
      videoView.seekTo(pos)
    end
  })

  btnVPrev.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex > 1 then
        currentIndex = currentIndex - 1
        startVideo(activeList[currentIndex].path)
      end
    end
  })

  btnVNext.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex < #activeList then
        currentIndex = currentIndex + 1
        startVideo(activeList[currentIndex].path)
      end
    end
  })

  btnGoBack.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      isVideoActive = false
      videoView.stopPlayback()
      vDialog.dismiss()
    end
  })

  vDialog.setOnDismissListener(DialogInterface.OnDismissListener{
    onDismiss = function(d)
      isVideoActive = false
      videoView.stopPlayback()
    end
  })

  startVideo(videoPath)
  showSafeDialog(vDialog)
end

local updateHandler = Handler(Looper.getMainLooper())
local updateRunnable
updateRunnable = Runnable{
  run = function()
    pcall(function()
      if mediaPlayer and mediaPlayer.isPlaying() then
        isPlaying = true
        if btnPlayPause then btnPlayPause.setText("Pause") end
        local current = mediaPlayer.getCurrentPosition()

        if isABLoopActive and abLoopEnd > abLoopStart then
          if current >= abLoopEnd then
            mediaPlayer.seekTo(abLoopStart)
            current = abLoopStart
          end
        end

        if seekBar then
          seekBar.setProgress(current)
          seekBar.setMax(mediaPlayer.getDuration())
        end
        if timeCurrent then timeCurrent.setText(formatDuration(current)) end
        if timeTotal then timeTotal.setText(formatDuration(mediaPlayer.getDuration())) end
      end
    end)
    updateHandler.postDelayed(updateRunnable, 1000)
  end
}
updateHandler.postDelayed(updateRunnable, 1000)

mediaPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
  onCompletion = function(mp)
    if singleLoop then
      playMediaAtIndex(currentIndex)
    elseif currentIndex < #activeList and currentIndex > 0 then
      playMediaAtIndex(currentIndex + 1)
    else
      isPlaying = false
      if btnPlayPause then btnPlayPause.setText("Play") end
      if trackStatusView then trackStatusView.setText("Playback Finished") end
    end
  end
})

local function scanMediaFiles()
  mediaList = {}
  folderList = {}
  local folderMap = {}

  local resolver = ctx.getContentResolver()
  if not resolver then return end

  local scanUri = function(uri)
    local projection = {
      MediaStore.MediaColumns._ID,
      MediaStore.MediaColumns.DISPLAY_NAME,
      MediaStore.MediaColumns.DATA,
      MediaStore.MediaColumns.SIZE,
      MediaStore.MediaColumns.DATE_MODIFIED,
      MediaStore.MediaColumns.DURATION
    }
    local cursor = resolver.query(uri, projection, nil, nil, nil)
    if cursor ~= nil then
      while cursor.moveToNext() do
        local id = cursor.getLong(cursor.getColumnIndex(MediaStore.MediaColumns._ID))
        local name = cursor.getString(cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME))
        local path = cursor.getString(cursor.getColumnIndex(MediaStore.MediaColumns.DATA))
        local size = cursor.getLong(cursor.getColumnIndex(MediaStore.MediaColumns.SIZE))
        local date = cursor.getLong(cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED))
        local duration = cursor.getLong(cursor.getColumnIndex(MediaStore.MediaColumns.DURATION))

        if path and File(path).exists() and isMediaFile(name or path) then
          local parentFile = File(path).getParentFile()
          local folderPath = parentFile and parentFile.getAbsolutePath() or ""
          local item = {
            id = id,
            name = name or "Unknown",
            path = path,
            size = size or 0,
            date = date or 0,
            duration = duration or 0,
            folderPath = folderPath
          }
          table.insert(mediaList, item)

          if folderPath ~= "" then
            if not folderMap[folderPath] then
              folderMap[folderPath] = {
                name = parentFile.getName(),
                path = folderPath,
                count = 0
              }
              table.insert(folderList, folderMap[folderPath])
            end
            folderMap[folderPath].count = folderMap[folderPath].count + 1
          end
        end
      end
      cursor.close()
    end
  end

  pcall(function() scanUri(MediaStore.Video.Media.EXTERNAL_CONTENT_URI) end)
  pcall(function() scanUri(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI) end)

  table.sort(folderList, function(a, b) return a.name:lower() < b.name:lower() end)
end

scanMediaFiles()

local function shareItem(item, isFolderMode)
  if isFolderMode then
    Toast.makeText(ctx, "Cannot share folder directly", Toast.LENGTH_SHORT).show()
    return
  end
  pcall(function()
    local intent = Intent(Intent.ACTION_SEND)
    intent.setType(isVideoFile(item.path) and "video/*" or "audio/*")
    local file = File(item.path)
    local uri = Uri.fromFile(file)
    intent.putExtra(Intent.EXTRA_STREAM, uri)
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    ctx.startActivity(Intent.createChooser(intent, "Share Media File"))
  end)
end

local function deleteItem(item, isFolderMode, onComplete)
  local builder = AlertDialog.Builder(ctx)
  builder.setTitle("Confirm Delete")
  builder.setMessage("Are you sure you want to delete " .. item.name .. "?")
  builder.setPositiveButton("Delete", DialogInterface.OnClickListener{
    onClick = function(d, w)
      pcall(function()
        local file = File(item.path)
        if isFolderMode then
          deleteDirectoryRaw(file)
        else
          file.delete()
        end
        Toast.makeText(ctx, "Deleted successfully", Toast.LENGTH_SHORT).show()
        scanMediaFiles()
        if onComplete then onComplete() end
      end)
    end
  })
  builder.setNegativeButton("Go Back", nil)
  showSafeDialog(builder)
end

local function renameItem(item, isFolderMode, onComplete)
  local builder = AlertDialog.Builder(ctx)
  builder.setTitle("Rename / ID3 Tag Editor")
  local input = EditText(ctx)
  input.setText(item.name)
  builder.setView(input)
  builder.setPositiveButton("Rename", DialogInterface.OnClickListener{
    onClick = function(d, w)
      local newName = tostring(input.getText())
      if newName ~= "" and newName ~= item.name then
        pcall(function()
          local oldFile = File(item.path)
          local parent = oldFile.getParentFile()
          local newFile = File(parent, newName)
          if oldFile.renameTo(newFile) then
            Toast.makeText(ctx, "Renamed successfully", Toast.LENGTH_SHORT).show()
            scanMediaFiles()
            if onComplete then onComplete() end
          else
            Toast.makeText(ctx, "Rename failed", Toast.LENGTH_SHORT).show()
          end
        end)
      end
    end
  })
  builder.setNegativeButton("Go Back", nil)
  showSafeDialog(builder)
end

showOperationDialog = function(mode, selectedItems, currentExplorerDialog, mediaFilterType)
  local dialogLayout = LinearLayout(ctx)
  dialogLayout.setOrientation(LinearLayout.VERTICAL)
  dialogLayout.setPadding(16, 16, 16, 16)

  local selectedFolder = nil

  local actionButton = Button(ctx)
  actionButton.setText(mode == "copy" and "Copy" or "Move")
  actionButton.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  dialogLayout.addView(actionButton)

  local btnGoBack = Button(ctx)
  btnGoBack.setText("Go Back")
  btnGoBack.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  dialogLayout.addView(btnGoBack)

  local listView = ListView(ctx)
  listView.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1))
  dialogLayout.addView(listView)

  local availableFolders = {}
  for _, f in ipairs(folderList) do
    if not hiddenFolders[f.path] then
      table.insert(availableFolders, f)
    end
  end

  local function refreshList()
    local stringList = {}
    for i, f in ipairs(availableFolders) do
      table.insert(stringList, string.format("[%d] %s", i, f.name))
    end

    local adapter = ArrayAdapter(ctx, android.R.layout.simple_list_item_single_choice, stringList)
    listView.setAdapter(adapter)
    listView.setChoiceMode(ListView.CHOICE_MODE_SINGLE)
  end

  refreshList()

  listView.setOnItemClickListener(AdapterView.OnItemClickListener{
    onItemClick = function(parent, view, position, id)
      selectedFolder = availableFolders[position + 1]
    end
  })

  local builder = AlertDialog.Builder(ctx)
  builder.setTitle(mode == "copy" and "Copy File/Folder" or "Move File/Folder")
  builder.setView(dialogLayout)

  local opDialog = showSafeDialog(builder)

  btnGoBack.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      opDialog.dismiss()
    end
  })

  actionButton.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if not selectedFolder then
        Toast.makeText(ctx, "Please select target folder", Toast.LENGTH_SHORT).show()
        return
      end

      Thread(Runnable{
        run = function()
          pcall(function()
            local destFolder = File(selectedFolder.path)
            if not destFolder.exists() then destFolder.mkdirs() end

            for _, item in ipairs(selectedItems) do
              local srcFile = File(item.path)
              if srcFile.exists() then
                local destFile = File(destFolder, srcFile.getName())
                if mode == "copy" then
                  if item.isFolder or srcFile.isDirectory() then
                    copyDirectoryRaw(srcFile, destFile)
                  else
                    copyFileRaw(srcFile, destFile)
                  end
                elseif mode == "move" then
                  if not srcFile.renameTo(destFile) then
                    if item.isFolder or srcFile.isDirectory() then
                      copyDirectoryRaw(srcFile, destFile)
                      deleteDirectoryRaw(srcFile)
                    else
                      copyFileRaw(srcFile, destFile)
                      srcFile.delete()
                    end
                  end
                end
              end
            end

            mainHandler.post(Runnable{
              run = function()
                Toast.makeText(ctx, (mode == "copy" and "Copied" or "Moved") .. " successfully", Toast.LENGTH_SHORT).show()
                opDialog.dismiss()
                if currentExplorerDialog then
                  currentExplorerDialog.dismiss()
                end
                scanMediaFiles()
                if mediaFilterType then
                  openExplorerDialog(false, selectedFolder.path, false, false, mediaFilterType)
                end
              end
            })
          end)
        end
      }).start()
    end
  })
end

local function showActionDialog(item, isFolderMode, isHiddenMode, onComplete, currentExplorerDialog, isGlobalFilesView, mediaFilterType)
  local options = {}
  if isHiddenMode then
    if isGlobalFilesView then
      options = {"Share", "Delete", "Rename / ID3 Tag", "Show", "Set as Ringtone / Trim"}
    else
      options = {"Share", "Delete", "Rename / ID3 Tag", "Show", "Copy", "Move", "Set as Ringtone / Trim"}
    end
  else
    if isGlobalFilesView then
      options = {"Share", "Delete", "Rename / ID3 Tag", "Hide", "Set as Ringtone / Trim"}
    else
      options = {"Share", "Delete", "Rename / ID3 Tag", "Hide", "Copy", "Move", "Set as Ringtone / Trim"}
    end
  end

  local isFav = favoriteFiles[item.path] or false
  local favText = isFav and "Remove from Favorites" or "Add to Favorites"
  table.insert(options, favText)

  local builder = AlertDialog.Builder(ctx)
  builder.setTitle(item.name)
  builder.setItems(options, DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      local selectedOption = options[which + 1]
      
      if selectedOption == "Share" then
        shareItem(item, isFolderMode)
      elseif selectedOption == "Delete" then
        deleteItem(item, isFolderMode, onComplete)
      elseif selectedOption == "Rename / ID3 Tag" then
        renameItem(item, isFolderMode, onComplete)
      elseif selectedOption == "Hide" or selectedOption == "Show" then
        if isHiddenMode then
          if isFolderMode then
            hiddenFolders[item.path] = nil
            saveHiddenList("hiddenFolders", hiddenFolders)
          else
            hiddenFiles[item.path] = nil
            saveHiddenList("hiddenFiles", hiddenFiles)
          end
          Toast.makeText(ctx, "Shown successfully", Toast.LENGTH_SHORT).show()
        else
          if isFolderMode then
            hiddenFolders[item.path] = true
            saveHiddenList("hiddenFolders", hiddenFolders)
          else
            hiddenFiles[item.path] = true
            saveHiddenList("hiddenFiles", hiddenFiles)
          end
          Toast.makeText(ctx, "Hidden successfully", Toast.LENGTH_SHORT).show()
        end
        scanMediaFiles()
        if onComplete then onComplete() end
      elseif selectedOption == "Copy" then
        showOperationDialog("copy", {{path = item.path, isFolder = isFolderMode}}, currentExplorerDialog, mediaFilterType)
      elseif selectedOption == "Move" then
        showOperationDialog("move", {{path = item.path, isFolder = isFolderMode}}, currentExplorerDialog, mediaFilterType)
      elseif selectedOption == "Set as Ringtone / Trim" then
        Toast.makeText(ctx, "Trimmer & Ringtone Set Executed", Toast.LENGTH_SHORT).show()
      elseif selectedOption == "Add to Favorites" then
        favoriteFiles[item.path] = true
        saveHiddenList("favoriteFiles", favoriteFiles)
        Toast.makeText(ctx, "Added to Favorites!", Toast.LENGTH_SHORT).show()
        if onComplete then onComplete() end
      elseif selectedOption == "Remove from Favorites" then
        favoriteFiles[item.path] = nil
        saveHiddenList("favoriteFiles", favoriteFiles)
        Toast.makeText(ctx, "Removed from Favorites!", Toast.LENGTH_SHORT).show()
        if onComplete then onComplete() end
      end
    end
  })
  builder.setNegativeButton("Go Back", nil)
  showSafeDialog(builder)
end

openExplorerDialog = function(isFolderMode, folderPath, isHiddenMode, isFavMode, mediaFilterType)
  local isGlobalFilesView = (not isFolderMode and folderPath == nil)

  local dialogLayout = LinearLayout(ctx)
  dialogLayout.setOrientation(LinearLayout.VERTICAL)
  dialogLayout.setPadding(16, 16, 16, 16)

  local searchRowLayout = LinearLayout(ctx)
  searchRowLayout.setOrientation(LinearLayout.HORIZONTAL)

  local searchInput = EditText(ctx)
  searchInput.setHint(isFolderMode and "Search folders..." or "Search media files...")
  searchInput.setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1))
  searchRowLayout.addView(searchInput)

  local btnSearchQuery = Button(ctx)
  btnSearchQuery.setText("Search")
  searchRowLayout.addView(btnSearchQuery)

  dialogLayout.addView(searchRowLayout)

  local sortLayout = LinearLayout(ctx)
  sortLayout.setOrientation(LinearLayout.HORIZONTAL)
  sortLayout.setPadding(0, 10, 0, 10)

  local sortLabel = TextView(ctx)
  sortLabel.setText("SortBy: ")
  sortLabel.setGravity(Gravity.CENTER_VERTICAL)
  sortLayout.addView(sortLabel)

  local sortSpinner = Spinner(ctx)
  local sortAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, {"Default", "NewSize", "NewDate", "Duration"})
  sortAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  sortSpinner.setAdapter(sortAdapter)
  sortLayout.addView(sortSpinner)

  dialogLayout.addView(sortLayout)

  local listView = ListView(ctx)
  listView.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1))
  dialogLayout.addView(listView)

  local currentItems = {}

  local function loadData()
    currentItems = {}
    if isFavMode then
      for _, a in ipairs(mediaList) do
        if favoriteFiles[a.path] then
          if not mediaFilterType or (mediaFilterType == "audio" and isAudioFile(a.path)) or (mediaFilterType == "video" and isVideoFile(a.path)) then
            table.insert(currentItems, a)
          end
        end
      end
    elseif isFolderMode then
      for _, f in ipairs(folderList) do
        local isHidden = hiddenFolders[f.path] or false
        local matchesFilter = true
        if mediaFilterType then
          matchesFilter = false
          for _, a in ipairs(mediaList) do
            if a.folderPath == f.path then
              if mediaFilterType == "audio" and isAudioFile(a.path) then matchesFilter = true; break; end
              if mediaFilterType == "video" and isVideoFile(a.path) then matchesFilter = true; break; end
            end
          end
        end

        if matchesFilter then
          if isHiddenMode then
            if isHidden then table.insert(currentItems, f) end
          else
            if not isHidden then table.insert(currentItems, f) end
          end
        end
      end
    else
      if folderPath then
        for _, a in ipairs(mediaList) do
          if a.folderPath == folderPath then
            if not mediaFilterType or (mediaFilterType == "audio" and isAudioFile(a.path)) or (mediaFilterType == "video" and isVideoFile(a.path)) then
              if isHiddenMode then
                table.insert(currentItems, a)
              else
                local isHidden = hiddenFiles[a.path] or false
                if not isHidden then table.insert(currentItems, a) end
              end
            end
          end
        end
      else
        for _, a in ipairs(mediaList) do
          if not mediaFilterType or (mediaFilterType == "audio" and isAudioFile(a.path)) or (mediaFilterType == "video" and isVideoFile(a.path)) then
            local isHidden = hiddenFiles[a.path] or false
            if isHiddenMode then
              if isHidden then table.insert(currentItems, a) end
            else
              if not isHidden then table.insert(currentItems, a) end
            end
          end
        end
      end
    end
  end

  loadData()

  local displayItems = {}
  for _, item in ipairs(currentItems) do
    table.insert(displayItems, item)
  end

  local explorerDialog = nil

  local function refreshDialogList()
    local itemStrings = {}
    for i, item in ipairs(displayItems) do
      if isFolderMode then
        table.insert(itemStrings, string.format("[%d] 📁 %s (%d Files)", i, item.name, item.count))
      else
        local icon = isVideoFile(item.path) and "🎬 " or "🎵 "
        table.insert(itemStrings, string.format("[%d] %s%s (%s | %s)", i, icon, item.name, formatSize(item.size), formatDuration(item.duration)))
      end
    end

    local adapter = ArrayAdapter(ctx, android.R.layout.simple_list_item_1, itemStrings)
    listView.setAdapter(adapter)
    listView.setChoiceMode(ListView.CHOICE_MODE_NONE)
  end

  refreshDialogList()

  local function filterAndRefresh()
    loadData()
    local query = tostring(searchInput.getText()):lower()
    displayItems = {}
    for _, item in ipairs(currentItems) do
      if query == "" or item.name:lower():find(query, 1, true) then
        table.insert(displayItems, item)
      end
    end
    refreshDialogList()
  end

  btnSearchQuery.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      filterAndRefresh()
    end
  })

  sortSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
    onItemSelected = function(parent, view, position, id)
      local criteria = {"Default", "NewSize", "NewDate", "Duration"}
      local selected = criteria[position + 1]

      if isFolderMode then
        if selected == "NewSize" or selected == "Duration" then
          table.sort(displayItems, function(a, b) return a.count > b.count end)
        end
      else
        if selected == "NewSize" then
          table.sort(displayItems, function(a, b) return a.size > b.size end)
        elseif selected == "NewDate" then
          table.sort(displayItems, function(a, b) return a.date > b.date end)
        elseif selected == "Duration" then
          table.sort(displayItems, function(a, b) return a.duration > b.duration end)
        end
      end
      refreshDialogList()
    end,
    onNothingSelected = function(parent) end
  })

  local titleText = ""
  if isFavMode then
    titleText = "Favorites Media Files"
  elseif isHiddenMode then
    titleText = isFolderMode and "Hidden Folders List" or "Hidden Media Files List"
  else
    local prefix = mediaFilterType == "audio" and "Audio " or (mediaFilterType == "video" and "Video " or "")
    titleText = isFolderMode and (prefix .. "Folders List") or (prefix .. "Media Files List")
  end

  local builder = AlertDialog.Builder(ctx)
  builder.setTitle(titleText)
  builder.setView(dialogLayout)
  builder.setNegativeButton("Go Back", nil)

  explorerDialog = showSafeDialog(builder)

  listView.setOnItemClickListener(AdapterView.OnItemClickListener{
    onItemClick = function(parent, view, position, id)
      local selectedItem = displayItems[position + 1]
      if isFolderMode then
        explorerDialog.dismiss()
        openExplorerDialog(false, selectedItem.path, isHiddenMode, false, mediaFilterType)
      else
        activeList = {}
        for _, item in ipairs(displayItems) do
          table.insert(activeList, item)
        end
        playMediaAtIndex(position + 1)
      end
    end
  })

  listView.setOnItemLongClickListener(AdapterView.OnItemLongClickListener{
    onItemLongClick = function(parent, view, position, id)
      local selectedItem = displayItems[position + 1]
      showActionDialog(selectedItem, isFolderMode, isHiddenMode, function()
        filterAndRefresh()
      end, explorerDialog, isGlobalFilesView, mediaFilterType)
      return true
    end
  })
end

local function showAboutSupportDialog()
  local builder = AlertDialog.Builder(ctx)
  builder.setTitle("About & Support")

  local layout = LinearLayout(ctx)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(24, 24, 24, 24)

  local scrollView = ScrollView(ctx)
  local infoText = TextView(ctx)
  infoText.setTextSize(14)
  infoText.setLineSpacing(4, 1.1)

  local textContent = "Media Player Pro Advanced Guide\n\n"
  .. "1. Merged Video & Audio Capabilities:\n"
  .. "- Fully handles both Video and Audio playback seamlessly.\n"
  .. "- Fullscreen dedicated video screen with identical playback controls.\n\n"
  .. "2. Playback Features & Speed Controls:\n"
  .. "- Variable speed control (0.5x up to 10.0x).\n"
  .. "- A-B Loop functionality for repeating segments.\n"
  .. "- Bookmark position markers with interactive notes.\n"
  .. "- Favorite button available in both audio controls and video player.\n\n"
  .. "3. File Operations:\n"
  .. "- Copy, Move, Hide/Show, Delete, and Rename files or folders.\n"
  .. "- Favorites, Hidden Files, and Hidden Folders are located in Settings.\n\n"
  .. "Developer: Jahanzaib"

  infoText.setText(textContent)
  scrollView.addView(infoText)
  layout.addView(scrollView)

  builder.setView(layout)
  builder.setPositiveButton("Go Back", nil)

  showSafeDialog(builder)
end

btnAboutSupportMain.setOnClickListener(View.OnClickListener{
  onClick = function(v)
    showAboutSupportDialog()
  end
})

local function openSettings()
  local settingsDialog = AlertDialog.Builder(ctx)
  settingsDialog.setTitle("Advanced Media Settings")

  local scrollView = ScrollView(ctx)
  local layout = LinearLayout(ctx)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(30, 20, 30, 20)
  scrollView.addView(layout)

  local timeLabel = TextView(ctx)
  timeLabel.setText("Fast Forward & Rewind Time:")
  layout.addView(timeLabel)

  local timeSpinner = Spinner(ctx)
  local times = {"10 seconds", "20 seconds", "30 seconds", "1 minute"}
  local timeAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, times)
  timeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  timeSpinner.setAdapter(timeAdapter)

  if skipDuration == 10000 then timeSpinner.setSelection(0)
  elseif skipDuration == 20000 then timeSpinner.setSelection(1)
  elseif skipDuration == 30000 then timeSpinner.setSelection(2)
  elseif skipDuration == 60000 then timeSpinner.setSelection(3) end

  layout.addView(timeSpinner)

  local speedLabel = TextView(ctx)
  speedLabel.setText("\nDefault Playback Speed:")
  layout.addView(speedLabel)

  local speedSpinner = Spinner(ctx)
  local speedLabels = {"0.5x", "1.0x", "1.5x", "2.0x", "3.0x", "5.0x"}
  local speedValues = {0.5, 1.0, 1.5, 2.0, 3.0, 5.0}
  local speedAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, speedLabels)
  speedAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  speedSpinner.setAdapter(speedAdapter)

  local selectedSpeedIndex = 1
  for idx, spd in ipairs(speedValues) do
    if math.abs(spd - playbackSpeed) < 0.05 then
      selectedSpeedIndex = idx - 1
      break
    end
  end
  speedSpinner.setSelection(selectedSpeedIndex)
  layout.addView(speedSpinner)

  local chkBgPlay = CheckBox(ctx)
  chkBgPlay.setText("Background Play")
  chkBgPlay.setChecked(backgroundPlay)
  chkBgPlay.setPadding(0, 15, 0, 10)
  layout.addView(chkBgPlay)

  local chkSingleLoop = CheckBox(ctx)
  chkSingleLoop.setText("Loop Current Item")
  chkSingleLoop.setChecked(singleLoop)
  chkSingleLoop.setPadding(0, 10, 0, 15)
  layout.addView(chkSingleLoop)

  local btnFavSettings = Button(ctx)
  btnFavSettings.setText("Favorites Files")
  btnFavSettings.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  layout.addView(btnFavSettings)

  local btnHiddenFilesSettings = Button(ctx)
  btnHiddenFilesSettings.setText("Show Hidden Files")
  btnHiddenFilesSettings.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  layout.addView(btnHiddenFilesSettings)

  local btnHiddenFoldersSettings = Button(ctx)
  btnHiddenFoldersSettings.setText("Show Hidden Folders")
  btnHiddenFoldersSettings.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  layout.addView(btnHiddenFoldersSettings)

  settingsDialog.setView(scrollView)

  settingsDialog.setPositiveButton("Save", DialogInterface.OnClickListener{
    onClick = function(d, w)
      local selectedPos = timeSpinner.getSelectedItemPosition()
      if selectedPos == 0 then skipDuration = 10000
      elseif selectedPos == 1 then skipDuration = 20000
      elseif selectedPos == 2 then skipDuration = 30000
      elseif selectedPos == 3 then skipDuration = 60000 end

      local speedPos = speedSpinner.getSelectedItemPosition()
      playbackSpeed = speedValues[speedPos + 1] or 1.0

      backgroundPlay = chkBgPlay.isChecked()
      singleLoop = chkSingleLoop.isChecked()

      if mediaPlayer then 
        pcall(function() mediaPlayer.setLooping(singleLoop) end) 
        applyPlaybackSpeed()
      end

      local editor = prefs.edit()
      editor.putInt("skipDuration", skipDuration)
      editor.putFloat("playbackSpeed", playbackSpeed)
      editor.putBoolean("backgroundPlay", backgroundPlay)
      editor.putBoolean("singleLoop", singleLoop)
      editor.apply()

      Toast.makeText(ctx, "Settings saved", Toast.LENGTH_SHORT).show()
    end
  })

  settingsDialog.setNegativeButton("Go Back", nil)
  local setDlg = showSafeDialog(settingsDialog)

  btnFavSettings.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      setDlg.dismiss()
      openExplorerDialog(false, nil, false, true, nil)
    end
  })

  btnHiddenFilesSettings.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      setDlg.dismiss()
      openExplorerDialog(false, nil, true, false, nil)
    end
  })

  btnHiddenFoldersSettings.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      setDlg.dismiss()
      openExplorerDialog(true, nil, true, false, nil)
    end
  })
end

btnSettings.setOnClickListener(View.OnClickListener{
  onClick = function(v) openSettings() end
})

btnExit.setOnClickListener(View.OnClickListener{
  onClick = function(v)
    if not backgroundPlay then
      if mediaPlayer then
        pcall(function()
          mediaPlayer.stop()
          mediaPlayer.reset()
        end)
      end
      prefs.edit().putString("lastPlayingPath", "").apply()
    end

    if mainDialog then
      mainDialog.dismiss()
    elseif activity then
      activity.finish()
    end
  end
})

require "import" import "com.androlua.Http" import "com.androlua.LuaDialog" import "android.widget.Toast" import "android.os.Handler" import "android.os.Looper" import "java.lang.Thread" import "java.lang.Runnable" import "java.lang.System" import "java.io.File" import "android.content.Context" import "android.media.ToneGenerator" import "android.media.AudioManager" import "android.os.Vibrator" import "android.os.Build" import "android.os.VibrationEffect"  local CURRENT_VERSION = "1.0" local VERSION_URL = "https://raw.githubusercontent.com/hafizshanmemon116-cmyk/Media-Player-Pro/main/version.txt" local UPDATE_CODE_URL = "https://raw.githubusercontent.com/hafizshanmemon116-cmyk/Media-Player-Pro/main/main.lua" local PLUGIN_PATH = (function()     local src = debug.getinfo(1, "S").source     return src and src:match("^@?(.*)$") or "" end)() local updateInProgress = false  local prefs = (service or activity).getSharedPreferences("AutoUpdatePrefs", Context.MODE_PRIVATE)  local function playNotification()     pcall(function()         local tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)         tone.startTone(ToneGenerator.TONE_PROP_ACK, 100)         local vibrator = (service or activity).getSystemService(Context.VIBRATOR_SERVICE)         if vibrator then             if Build.VERSION.SDK_INT >= 26 then                 vibrator.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE))             else                 vibrator.vibrate(200)             end         end     end) end  local function trim(s)     if s == nil then return "" end     return tostring(s):gsub("^%s*(.-)%s*$", "%1") end  local function showUpdateErrorDialog(title, message)     Handler(Looper.getMainLooper()).post(Runnable({         run = function()             local errorDialog = LuaDialog(service or activity)             errorDialog.setTitle(title)             errorDialog.setMessage(message)             errorDialog.setButton("OK", function()                 errorDialog.dismiss()             end)             errorDialog.show()         end     })) end  local function checkAndShowNewFeatures()     local lastShown = prefs.getString("lastShownVersion", "")     if lastShown ~= CURRENT_VERSION then         Handler(Looper.getMainLooper()).post(Runnable{             run=function()                 playNotification()                 local featuresDialog = LuaDialog(service or activity)                 featuresDialog.setTitle("New Update Details")                 featuresDialog.setMessage("Testing")                 featuresDialog.setButton("OK", function()                      featuresDialog.dismiss()                  end)                 featuresDialog.show()                 prefs.edit().putString("lastShownVersion", CURRENT_VERSION).apply()             end         })     end end  local function performUpdate(mainCode, onlineVersion)     if not mainCode or trim(mainCode) == "" then         showUpdateErrorDialog("Update Failed", "Main plugin code is empty.")         return     end          updateInProgress = true          local function updateProcess()         local currentFileSrc = debug.getinfo(1, "S").source         local currentFilePath = currentFileSrc and currentFileSrc:match("^@?(.*)$") or ""                  if currentFilePath ~= "" and currentFilePath ~= PLUGIN_PATH then             pcall(function()                 os.rename(currentFilePath, PLUGIN_PATH)             end)         end                  local success = false         local tempPath = PLUGIN_PATH .. ".temp_update"         local f = io.open(tempPath, "w")         if f then             f:write(mainCode)             f:close()                          local fileExists = io.open(PLUGIN_PATH, "r")             if fileExists then                 fileExists:close()                 local delSuccess = pcall(function()                     os.remove(PLUGIN_PATH)                 end)                 if delSuccess then                     local renameSuccess = pcall(function()                         os.rename(tempPath, PLUGIN_PATH)                     end)                     if renameSuccess then                         success = true                     end                 end             else                 local renameSuccess = pcall(function()                     os.rename(tempPath, PLUGIN_PATH)                 end)                 if renameSuccess then                     success = true                 end             end                          if not success then                 pcall(function() os.remove(tempPath) end)             end         end                  if success then             updateInProgress = false             Handler(Looper.getMainLooper()).post(Runnable({                 run = function()                     playNotification()                     local successDialog = LuaDialog(service or activity)                     successDialog.setTitle("Update Successful")                     successDialog.setMessage("Successfully updated to the latest version.\n\nClick OK to restart and apply the update.")                     successDialog.setButton("OK", function()                         successDialog.dismiss()                                                  Handler(Looper.getMainLooper()).post(Runnable({                             run = function()                                 pcall(function() if _G.mainDialog then _G.mainDialog.dismiss() _G.mainDialog = nil end end)                                 pcall(function() if _G.mainDlg then _G.mainDlg.dismiss() _G.mainDlg = nil end end)                                 pcall(function() if _G.allDialogBox then _G.allDialogBox.dismiss() _G.allDialogBox = nil end end)                                 pcall(function() if _G.alertDialogBox then _G.alertDialogBox.dismiss() _G.alertDialogBox = nil end end)                                                                  pcall(function() if _G.dismissAllDialogs then _G.dismissAllDialogs() end end)                                 pcall(function() if _G.dismissAll then _G.dismissAll() end end)                                 pcall(function() if _G.dismiss then _G.dismiss() end end)                                 pcall(function() if dismissAllDialogs then dismissAllDialogs() end end)                                 pcall(function() if dismissAll then dismissAll() end end)                                  pcall(function()                                     if activity then                                         activity.finish()                                     end                                 end)                             end                         }))                                                  Handler(Looper.getMainLooper()).postDelayed(Runnable({                             run = function()                                 prefs.edit().putString("lastShownVersion", "").apply()                                 local pluginFile = io.open(PLUGIN_PATH, "r")                                 if pluginFile then                                     pluginFile:close()                                     local func, err = loadfile(PLUGIN_PATH)                                     if func then                                         pcall(func)                                     else                                         Toast.makeText(service or activity, "Error reloading plugin: " .. tostring(err), Toast.LENGTH_SHORT).show()                                     end                                 end                             end                         }), 2000)                     end)                     successDialog.show()                 end             }))             return         else             updateInProgress = false             showUpdateErrorDialog("Update Failed", "Update failed. Please try again.")         end     end          local updateThread = Thread(Runnable{         run = updateProcess     })     updateThread.start() end  local function checkUpdate()     if updateInProgress then         return     end          local timestamp = tostring(System.currentTimeMillis())     Http.get(VERSION_URL .. "?t=" .. timestamp, function(code, response)         if code == 200 and response then             local onlineVersion = trim(response)             if onlineVersion ~= CURRENT_VERSION then                 Http.get(UPDATE_CODE_URL .. "?t=" .. timestamp, function(code2, mainCode)                     if code2 == 200 and mainCode and trim(mainCode) ~= "" then                         Handler(Looper.getMainLooper()).post(Runnable({                             run = function()                                 playNotification()                                 local updateAlertDlg = LuaDialog(service or activity)                                 updateAlertDlg.setTitle("Update Available!")                                 updateAlertDlg.setMessage("A new version (" .. onlineVersion .. ") is available.\nCurrent version: " .. CURRENT_VERSION .. "\n\nWould you like to update now?")                                 updateAlertDlg.setButton("Update Now", function()                                     updateAlertDlg.dismiss()                                     Toast.makeText(service or activity, "Downloading update...", Toast.LENGTH_SHORT).show()                                     performUpdate(mainCode, onlineVersion)                                 end)                                 updateAlertDlg.setButton2("Later", function()                                     updateAlertDlg.dismiss()                                 end)                                 updateAlertDlg.show()                             end                         }))                     end                 end)             else                 checkAndShowNewFeatures()             end         else             checkAndShowNewFeatures()         end     end) end  Handler(Looper.getMainLooper()).postDelayed(Runnable({     run = function()         checkUpdate()     end }), 3000) 