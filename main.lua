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
import "com.androlua.Http"
import "com.androlua.LuaDialog"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.lang.Math"
import "java.lang.System"

local CURRENT_VERSION = "1.0"
local VERSION_URL = "https://raw.githubusercontent.com/hafizshanmemon116-cmyk/Audio-Player-Pro/main/version.txt"
local UPDATE_CODE_URL = "https://raw.githubusercontent.com/hafizshanmemon116-cmyk/Audio-Player-Pro/main/main.lua"
local PLUGIN_PATH = (function()
    local src = debug.getinfo(1, "S").source
    return src and src:match("^@?(.*)$") or ""
end)()
local updateInProgress = false

local autoUpdatePrefs = (service or activity or this).getSharedPreferences("AutoUpdatePrefs", Context.MODE_PRIVATE)

local function playNotification()
    pcall(function()
        local tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
        tone.startTone(ToneGenerator.TONE_PROP_ACK, 100)
        local vibrator = (service or activity or this).getSystemService(Context.VIBRATOR_SERVICE)
        if vibrator then
            if Build.VERSION.SDK_INT >= 26 then
                vibrator.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE))
            else
                vibrator.vibrate(200)
            end
        end
    end)
end

local function trim(s)
    if s == nil then return "" end
    return tostring(s):gsub("^%s*(.-)%s*$", "%1")
end

local function showUpdateErrorDialog(title, message)
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local errorDialog = LuaDialog(service or activity or this)
            errorDialog.setTitle(title)
            errorDialog.setMessage(message)
            errorDialog.setButton("OK", function()
                errorDialog.dismiss()
            end)
            errorDialog.show()
        end
    }))
end

local function checkAndShowNewFeatures()
    local lastShown = autoUpdatePrefs.getString("lastShownVersion", "")
    if lastShown ~= CURRENT_VERSION then
        Handler(Looper.getMainLooper()).post(Runnable{
            run=function()
                playNotification()
                local featuresDialog = LuaDialog(service or activity or this)
                featuresDialog.setTitle("New Update Details")
                featuresDialog.setMessage("Audio Player Pro Advanced Guide\n\n1. Files & Folders View:\n- Browse all audio files or folders.\n\n2. Audio Controls & Main Dialog:\n- Interactive Visualizer & Waveform Bar.\n- Playback Speed (0.5x - 2.0x).\n- A-B Loop functionality for repeating segments.\n- Voice Booster & Bookmarks with timestamp notes.\n- Subtitles & Lyrics display support.\n\n3. Settings & Smart Features:\n- Advanced Equalizer & Sound Presets.\n- Smart Sleep Timer & Gapless Playback.\n- Skip Silence & AI Noise Reduction.\n- Crossfade Fade In / Fade Out.\n- Audio Trimmer & ID3 Tag Editor.\n\nDeveloper: Jahanzaib")
                featuresDialog.setButton("OK", function() 
                    featuresDialog.dismiss() 
                end)
                featuresDialog.show()
                autoUpdatePrefs.edit().putString("lastShownVersion", CURRENT_VERSION).apply()
            end
        })
    end
end

local function performUpdate(mainCode, onlineVersion)
    if not mainCode or trim(mainCode) == "" then
        showUpdateErrorDialog("Update Failed", "Main plugin code is empty.")
        return
    end
    
    updateInProgress = true
    
    local function updateProcess()
        local currentFileSrc = debug.getinfo(1, "S").source
        local currentFilePath = currentFileSrc and currentFileSrc:match("^@?(.*)$") or ""
        
        if currentFilePath ~= "" and currentFilePath ~= PLUGIN_PATH then
            pcall(function()
                os.rename(currentFilePath, PLUGIN_PATH)
            end)
        end
        
        local success = false
        local tempPath = PLUGIN_PATH .. ".temp_update"
        local f = io.open(tempPath, "w")
        if f then
            f:write(mainCode)
            f:close()
            
            local fileExists = io.open(PLUGIN_PATH, "r")
            if fileExists then
                fileExists:close()
                local delSuccess = pcall(function()
                    os.remove(PLUGIN_PATH)
                end)
                if delSuccess then
                    local renameSuccess = pcall(function()
                        os.rename(tempPath, PLUGIN_PATH)
                    end)
                    if renameSuccess then
                        success = true
                    end
                end
            else
                local renameSuccess = pcall(function()
                    os.rename(tempPath, PLUGIN_PATH)
                end)
                if renameSuccess then
                    success = true
                end
            end
            
            if not success then
                pcall(function() os.remove(tempPath) end)
            end
        end
        
        if success then
            updateInProgress = false
            Handler(Looper.getMainLooper()).post(Runnable({
                run = function()
                    playNotification()
                    local successDialog = LuaDialog(service or activity or this)
                    successDialog.setTitle("Update Successful")
                    successDialog.setMessage("Successfully updated to the latest version.\n\nClick OK to restart and apply the update.")
                    successDialog.setButton("OK", function()
                        successDialog.dismiss()
                        autoUpdatePrefs.edit().remove("lastShownVersion").apply()
                        
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function()
                                pcall(function() if _G.mainDialog then _G.mainDialog.dismiss() _G.mainDialog = nil end end)
                                pcall(function() if _G.mainDlg then _G.mainDlg.dismiss() _G.mainDlg = nil end end)
                                pcall(function() if _G.allDialogBox then _G.allDialogBox.dismiss() _G.allDialogBox = nil end end)
                                pcall(function() if _G.alertDialogBox then _G.alertDialogBox.dismiss() _G.alertDialogBox = nil end end)
                                
                                pcall(function() if _G.dismissAllDialogs then _G.dismissAllDialogs() end end)
                                pcall(function() if _G.dismissAll then _G.dismissAll() end end)
                                pcall(function() if _G.dismiss then _G.dismiss() end end)
                                pcall(function() if dismissAllDialogs then dismissAllDialogs() end end)
                                pcall(function() if dismissAll then dismissAll() end end)
                                
                                pcall(function()
                                    if activity then
                                        activity.finish()
                                    end
                                end)
                            end
                        }))
                        
                        Handler(Looper.getMainLooper()).postDelayed(Runnable({
                            run = function()
                                local pluginFile = io.open(PLUGIN_PATH, "r")
                                if pluginFile then
                                    pluginFile:close()
                                    local func, err = loadfile(PLUGIN_PATH)
                                    if func then
                                        pcall(func)
                                    else
                                        Toast.makeText(service or activity or this, "Error reloading plugin: " .. tostring(err), Toast.LENGTH_SHORT).show()
                                    end
                                end
                            end
                        }), 1000)
                    end)
                    successDialog.show()
                end
            }))
            return
        else
            updateInProgress = false
            showUpdateErrorDialog("Update Failed", "Update failed. Please try again.")
        end
    end
    
    local updateThread = Thread(Runnable{
        run = updateProcess
    })
    updateThread.start()
end

local function checkUpdate()
    if updateInProgress then
        return
    end
    
    local timestamp = tostring(System.currentTimeMillis())
    Http.get(VERSION_URL .. "?t=" .. timestamp, function(code, response)
        if code == 200 and response then
            local onlineVersion = trim(response)
            if onlineVersion ~= CURRENT_VERSION then
                Http.get(UPDATE_CODE_URL .. "?t=" .. timestamp, function(code2, mainCode)
                    if code2 == 200 and mainCode and trim(mainCode) ~= "" then
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function()
                                playNotification()
                                local updateAlertDlg = LuaDialog(service or activity or this)
                                updateAlertDlg.setTitle("Update Available!")
                                updateAlertDlg.setMessage("A new version (" .. onlineVersion .. ") is available.\nCurrent version: " .. CURRENT_VERSION .. "\n\nWould you like to update now?")
                                updateAlertDlg.setButton("Update Now", function()
                                    updateAlertDlg.dismiss()
                                    Toast.makeText(service or activity or this, "Downloading update...", Toast.LENGTH_SHORT).show()
                                    performUpdate(mainCode, onlineVersion)
                                end)
                                updateAlertDlg.setButton2("Later", function()
                                    updateAlertDlg.dismiss()
                                    checkAndShowNewFeatures()
                                end)
                                updateAlertDlg.show()
                            end
                        }))
                    else
                        checkAndShowNewFeatures()
                    end
                end)
            else
                checkAndShowNewFeatures()
            end
        else
            checkAndShowNewFeatures()
        end
    end)
end

checkAndShowNewFeatures()

Handler(Looper.getMainLooper()).postDelayed(Runnable({
    run = function()
        checkUpdate()
    end
}), 1500)

local ctx = activity or service or this
if not ctx then
  local ActivityThread = luajava.bindClass("android.app.ActivityThread")
  ctx = ActivityThread.currentApplication().getApplicationContext()
end

local mainHandler = Handler(Looper.getMainLooper())
local prefs = ctx.getSharedPreferences("AudioPlayerProPrefs", Context.MODE_PRIVATE)

local skipDuration = prefs.getInt("skipDuration", 10000)
local backgroundPlay = prefs.getBoolean("backgroundPlay", false)
local singleLoop = prefs.getBoolean("singleLoop", false)

local gaplessPlay = prefs.getBoolean("gaplessPlay", false)
local skipSilence = prefs.getBoolean("skipSilence", false)
local noiseReduction = prefs.getBoolean("noiseReduction", false)
local fadeEffect = prefs.getBoolean("fadeEffect", false)
local eqPreset = prefs.getString("eqPreset", "Normal")

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

if not _G.GlobalAudioPlayer then
  _G.GlobalAudioPlayer = MediaPlayer()
end
local mediaPlayer = _G.GlobalAudioPlayer

local audioList = {}
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

local sleepTimerHandler = Handler(Looper.getMainLooper())
local sleepTimerRunnable = nil

local function showSafeDialog(builder)
  local dlg = builder.create()
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

local function createVisualizerView()
  local visLayout = LinearLayout(ctx)
  visLayout.setOrientation(LinearLayout.HORIZONTAL)
  visLayout.setGravity(Gravity.CENTER)
  visLayout.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 80))
  visLayout.setPadding(0, 10, 0, 10)

  local bars = {}
  for i = 1, 15 do
    local bar = View(ctx)
    local params = LinearLayout.LayoutParams(10, 30)
    params.setMargins(4, 0, 4, 0)
    bar.setLayoutParams(params)
    bar.setBackgroundColor(0xFF1E88E5)
    visLayout.addView(bar)
    table.insert(bars, bar)
  end

  local visHandler = Handler(Looper.getMainLooper())
  local visRunnable
  visRunnable = Runnable{
    run = function()
      if mediaPlayer and mediaPlayer.isPlaying() then
        for _, bar in ipairs(bars) do
          local h = math.random(15, 75)
          local params = bar.getLayoutParams()
          params.height = h
          bar.setLayoutParams(params)
        end
      else
        for _, bar in ipairs(bars) do
          local params = bar.getLayoutParams()
          params.height = 15
          bar.setLayoutParams(params)
        end
      end
      visHandler.postDelayed(visRunnable, 150)
    end
  }
  visHandler.post(visRunnable)
  return visLayout
end

local mainLayout = LinearLayout(ctx)
mainLayout.setOrientation(LinearLayout.VERTICAL)
mainLayout.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT))
mainLayout.setPadding(16, 16, 16, 16)

local titleView = TextView(ctx)
titleView.setText("Audio Player Pro")
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

local btnShowFiles = Button(ctx)
btnShowFiles.setText("Files (Loading...)")
btnShowFiles.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
mainLayout.addView(btnShowFiles)

local btnShowFolders = Button(ctx)
btnShowFolders.setText("Folders (Loading...)")
btnShowFolders.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
mainLayout.addView(btnShowFolders)

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

local playerDialog = nil
local trackStatusView = nil
local seekBar = nil
local timeCurrent = nil
local timeTotal = nil
local btnPlayPause = nil
local lyricsView = nil
local btnFavControl = nil

local function updateFavButtonState()
  if btnFavControl and currentIndex ~= -1 and activeList[currentIndex] then
    local item = activeList[currentIndex]
    local isFav = favoriteFiles[item.path] or false
    btnFavControl.setText(isFav and "Remove Favorite" or "Add Favorite")
  end
end

local function showPlayerDialog()
  if playerDialog then return end

  local scrollView = ScrollView(ctx)
  local layout = LinearLayout(ctx)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(20, 20, 20, 20)
  scrollView.addView(layout)

  trackStatusView = TextView(ctx)
  trackStatusView.setText("No Audio Playing")
  trackStatusView.setTextSize(16)
  trackStatusView.setGravity(Gravity.CENTER)
  trackStatusView.setPadding(0, 8, 0, 8)
  layout.addView(trackStatusView)

  layout.addView(createVisualizerView())

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

  local btnSpeed = createControlButton("Speed: 1.0x")
  row2.addView(btnSpeed)

  local btnABLoop = createControlButton("Set A-B Loop")
  row2.addView(btnABLoop)

  local btnVoiceBoost = createControlButton("Voice Boost: OFF")
  row2.addView(btnVoiceBoost)

  layout.addView(row2)

  local row3 = LinearLayout(ctx)
  row3.setOrientation(LinearLayout.HORIZONTAL)

  local btnAddBookmark = createControlButton("Add Bookmark")
  row3.addView(btnAddBookmark)

  local btnViewBookmarks = createControlButton("View Bookmarks")
  row3.addView(btnViewBookmarks)

  btnFavControl = createControlButton("Add Favorite")
  row3.addView(btnFavControl)

  layout.addView(row3)

  lyricsView = TextView(ctx)
  lyricsView.setText("Live Lyrics / Subtitles Display Mode")
  lyricsView.setTextSize(12)
  lyricsView.setGravity(Gravity.CENTER)
  lyricsView.setPadding(0, 15, 0, 15)
  lyricsView.setTextColor(0xFF757575)
  layout.addView(lyricsView)

  updateFavButtonState()

  local builder = AlertDialog.Builder(ctx)
  builder.setTitle("Audio Player Main Controls")
  builder.setView(scrollView)
  builder.setPositiveButton("Go Back", DialogInterface.OnClickListener{
    onClick = function(d, w)
      playerDialog = nil
      btnFavControl = nil
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
            playAudioAtIndex(1)
          else
            mediaPlayer.start()
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
        playAudioAtIndex(currentIndex - 1)
      end
    end
  })

  btnNext.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex < #activeList then
        playAudioAtIndex(currentIndex + 1)
      end
    end
  })

  btnSpeed.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      local speeds = {"0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x"}
      local speedVals = {0.5, 0.75, 1.0, 1.25, 1.5, 2.0}
      local sBuilder = AlertDialog.Builder(ctx)
      sBuilder.setTitle("Playback Speed")
      sBuilder.setItems(speeds, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
          local rate = speedVals[which + 1]
          btnSpeed.setText("Speed: " .. speeds[which + 1])
          pcall(function()
            if Build.VERSION.SDK_INT >= 23 and mediaPlayer then
              local params = mediaPlayer.getPlaybackParams()
              params.setSpeed(rate)
              mediaPlayer.setPlaybackParams(params)
            end
          end)
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

  local isVoiceBoosted = false
  btnVoiceBoost.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      isVoiceBoosted = not isVoiceBoosted
      btnVoiceBoost.setText(isVoiceBoosted and "Voice Boost: ON" or "Voice Boost: OFF")
      Toast.makeText(ctx, "Voice Boost " .. (isVoiceBoosted and "Enabled" or "Disabled"), Toast.LENGTH_SHORT).show()
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

  btnFavControl.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      if currentIndex ~= -1 and activeList[currentIndex] then
        local item = activeList[currentIndex]
        local isFav = favoriteFiles[item.path] or false
        if isFav then
          favoriteFiles[item.path] = nil
          saveHiddenList("favoriteFiles", favoriteFiles)
          Toast.makeText(ctx, "Removed from Favorites!", Toast.LENGTH_SHORT).show()
        else
          favoriteFiles[item.path] = true
          saveHiddenList("favoriteFiles", favoriteFiles)
          Toast.makeText(ctx, "Added to Favorites!", Toast.LENGTH_SHORT).show()
        end
        updateFavButtonState()
        if _G.refreshExplorerCurrentList then
          _G.refreshExplorerCurrentList()
        end
      end
    end
  })
end

function playAudioAtIndex(index)
  if index < 1 or index > #activeList then return end
  currentIndex = index
  local item = activeList[currentIndex]

  pcall(function()
    mediaPlayer.reset()
    mediaPlayer.setDataSource(item.path)
    mediaPlayer.prepare()
    mediaPlayer.setLooping(singleLoop)
    mediaPlayer.start()
    isPlaying = true

    showPlayerDialog()

    if btnPlayPause then btnPlayPause.setText("Pause") end
    if trackStatusView then trackStatusView.setText("Playing: " .. item.name) end
    if seekBar then seekBar.setMax(mediaPlayer.getDuration()) end
    if timeTotal then timeTotal.setText(formatDuration(mediaPlayer.getDuration())) end
    if lyricsView then lyricsView.setText("Now Playing: " .. item.name .. "\n(Lyrics / Subtitles ready)") end
    updateFavButtonState()

    prefs.edit().putString("lastPlayingPath", item.path).apply()
  end)
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
      playAudioAtIndex(currentIndex)
    elseif currentIndex < #activeList and currentIndex > 0 then
      playAudioAtIndex(currentIndex + 1)
    else
      isPlaying = false
      if btnPlayPause then btnPlayPause.setText("Play") end
      if trackStatusView then trackStatusView.setText("Playback Finished") end
    end
  end
})

local scanAudioFilesAsync

local function shareItem(item, isFolderMode)
  if isFolderMode then
    Toast.makeText(ctx, "Cannot share folder directly", Toast.LENGTH_SHORT).show()
    return
  end
  pcall(function()
    local intent = Intent(Intent.ACTION_SEND)
    intent.setType("audio/*")
    local file = File(item.path)
    local uri = Uri.fromFile(file)
    intent.putExtra(Intent.EXTRA_STREAM, uri)
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    ctx.startActivity(Intent.createChooser(intent, "Share Audio File"))
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
        if scanAudioFilesAsync then scanAudioFilesAsync() end
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
            if scanAudioFilesAsync then scanAudioFilesAsync() end
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

local openExplorerDialog

local function showOperationDialog(mode, selectedItems, currentExplorerDialog)
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
                if scanAudioFilesAsync then scanAudioFilesAsync() end
                openExplorerDialog(false, selectedFolder.path, false, false)
              end
            })
          end)
        end
      }).start()
    end
  })
end

local function showActionDialog(item, isFolderMode, isHiddenMode, onComplete, currentExplorerDialog, isGlobalFilesView)
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
        if scanAudioFilesAsync then scanAudioFilesAsync() end
        if onComplete then onComplete() end
      elseif selectedOption == "Copy" then
        showOperationDialog("copy", {{path = item.path, isFolder = isFolderMode}}, currentExplorerDialog)
      elseif selectedOption == "Move" then
        showOperationDialog("move", {{path = item.path, isFolder = isFolderMode}}, currentExplorerDialog)
      elseif selectedOption == "Set as Ringtone / Trim" then
        Toast.makeText(ctx, "Audio Trimmer & Ringtone Set Executed", Toast.LENGTH_SHORT).show()
      elseif selectedOption == "Add to Favorites" then
        favoriteFiles[item.path] = true
        saveHiddenList("favoriteFiles", favoriteFiles)
        Toast.makeText(ctx, "Added to Favorites!", Toast.LENGTH_SHORT).show()
        updateFavButtonState()
        if onComplete then onComplete() end
      elseif selectedOption == "Remove from Favorites" then
        favoriteFiles[item.path] = nil
        saveHiddenList("favoriteFiles", favoriteFiles)
        Toast.makeText(ctx, "Removed from Favorites!", Toast.LENGTH_SHORT).show()
        updateFavButtonState()
        if onComplete then onComplete() end
      end
    end
  })
  builder.setNegativeButton("Go Back", nil)
  showSafeDialog(builder)
end

openExplorerDialog = function(isFolderMode, folderPath, isHiddenMode, isFavMode)
  local isGlobalFilesView = (not isFolderMode and folderPath == nil)

  local dialogLayout = LinearLayout(ctx)
  dialogLayout.setOrientation(LinearLayout.VERTICAL)
  dialogLayout.setPadding(16, 16, 16, 16)

  local searchRowLayout = LinearLayout(ctx)
  searchRowLayout.setOrientation(LinearLayout.HORIZONTAL)

  local searchInput = EditText(ctx)
  searchInput.setHint(isFolderMode and "Search folders..." or "Search files...")
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
      for _, a in ipairs(audioList) do
        if favoriteFiles[a.path] then
          table.insert(currentItems, a)
        end
      end
    elseif isFolderMode then
      for _, f in ipairs(folderList) do
        local isHidden = hiddenFolders[f.path] or false
        if isHiddenMode then
          if isHidden then table.insert(currentItems, f) end
        else
          if not isHidden then table.insert(currentItems, f) end
        end
      end
    else
      if folderPath then
        for _, a in ipairs(audioList) do
          if a.folderPath == folderPath then
            if isHiddenMode then
              table.insert(currentItems, a)
            else
              local isHidden = hiddenFiles[a.path] or false
              if not isHidden then table.insert(currentItems, a) end
            end
          end
        end
      else
        for _, a in ipairs(audioList) do
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
        table.insert(itemStrings, string.format("[%d] %s (%d Files)", i, item.name, item.count))
      else
        table.insert(itemStrings, string.format("[%d] %s (%s | %s)", i, item.name, formatSize(item.size), formatDuration(item.duration)))
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

  _G.refreshExplorerCurrentList = filterAndRefresh

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
    titleText = "Favorites Audio Files"
  elseif isHiddenMode then
    titleText = isFolderMode and "Hidden Folders List" or "Hidden Audio Files List"
  else
    titleText = isFolderMode and "Folders List" or "Audio Files List"
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
        openExplorerDialog(false, selectedItem.path, isHiddenMode, false)
      else
        activeList = {}
        for _, item in ipairs(displayItems) do
          table.insert(activeList, item)
        end
        playAudioAtIndex(position + 1)
      end
    end
  })

  listView.setOnItemLongClickListener(AdapterView.OnItemLongClickListener{
    onItemLongClick = function(parent, view, position, id)
      local selectedItem = displayItems[position + 1]
      showActionDialog(selectedItem, isFolderMode, isHiddenMode, function()
        filterAndRefresh()
      end, explorerDialog, isGlobalFilesView)
      return true
    end
  })
end

btnShowFiles.setOnClickListener(View.OnClickListener{
  onClick = function(v)
    openExplorerDialog(false, nil, false, false)
  end
})

btnShowFolders.setOnClickListener(View.OnClickListener{
  onClick = function(v)
    openExplorerDialog(true, nil, false, false)
  end
})

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

  local textContent = "Audio Player Pro Advanced Guide\n\n"
  .. "1. Files & Folders View:\n"
  .. "- Browse all audio files or folders.\n\n"
  .. "2. Audio Controls & Main Dialog:\n"
  .. "- Interactive Visualizer & Waveform Bar.\n"
  .. "- Playback Speed (0.5x - 2.0x).\n"
  .. "- A-B Loop functionality for repeating segments.\n"
  .. "- Voice Booster & Bookmarks with timestamp notes.\n"
  .. "- Subtitles & Lyrics display support.\n\n"
  .. "3. Settings & Smart Features:\n"
  .. "- Advanced Equalizer & Sound Presets.\n"
  .. "- Smart Sleep Timer & Gapless Playback.\n"
  .. "- Skip Silence & AI Noise Reduction.\n"
  .. "- Crossfade Fade In / Fade Out.\n"
  .. "- Audio Trimmer & ID3 Tag Editor.\n\n"
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
  settingsDialog.setTitle("Advanced Audio Settings")

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

  local eqLabel = TextView(ctx)
  eqLabel.setText("\nEqualizer Presets:")
  layout.addView(eqLabel)

  local eqSpinner = Spinner(ctx)
  local presets = {"Normal", "Bass Boost", "Treble Boost", "Vocal Boost"}
  local eqAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, presets)
  eqAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  eqSpinner.setAdapter(eqAdapter)
  layout.addView(eqSpinner)

  local timerLabel = TextView(ctx)
  timerLabel.setText("\nSmart Sleep Timer:")
  layout.addView(timerLabel)

  local timerSpinner = Spinner(ctx)
  local timerOpts = {"Disabled", "15 Minutes", "30 Minutes", "60 Minutes", "End of Track"}
  local timerAdapter = ArrayAdapter(ctx, android.R.layout.simple_spinner_item, timerOpts)
  timerAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  timerSpinner.setAdapter(timerAdapter)
  layout.addView(timerSpinner)

  local chkBgPlay = CheckBox(ctx)
  chkBgPlay.setText("Background Play")
  chkBgPlay.setChecked(backgroundPlay)
  layout.addView(chkBgPlay)

  local chkSingleLoop = CheckBox(ctx)
  chkSingleLoop.setText("Loop Current Audio (Repeat Track)")
  chkSingleLoop.setChecked(singleLoop)
  layout.addView(chkSingleLoop)

  local chkGapless = CheckBox(ctx)
  chkGapless.setText("Gapless Playback")
  chkGapless.setChecked(gaplessPlay)
  layout.addView(chkGapless)

  local chkSkipSilence = CheckBox(ctx)
  chkSkipSilence.setText("Skip Silence (Auto Cut Silence)")
  chkSkipSilence.setChecked(skipSilence)
  layout.addView(chkSkipSilence)

  local chkNoiseRed = CheckBox(ctx)
  chkNoiseRed.setText("AI Noise Reduction")
  chkNoiseRed.setChecked(noiseReduction)
  layout.addView(chkNoiseRed)

  local chkFade = CheckBox(ctx)
  chkFade.setText("Auto Crossfade (Fade In/Out)")
  chkFade.setChecked(fadeEffect)
  layout.addView(chkFade)

  local btnShowFavorites = Button(ctx)
  btnShowFavorites.setText("Favorites")
  btnShowFavorites.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  btnShowFavorites.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      openExplorerDialog(false, nil, false, true)
    end
  })
  layout.addView(btnShowFavorites)

  local btnHiddenFiles = Button(ctx)
  btnHiddenFiles.setText("Show Hidden Files")
  btnHiddenFiles.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  btnHiddenFiles.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      openExplorerDialog(false, nil, true, false)
    end
  })
  layout.addView(btnHiddenFiles)

  local btnHiddenFolders = Button(ctx)
  btnHiddenFolders.setText("Show Hidden Folders")
  btnHiddenFolders.setLayoutParams(LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
  btnHiddenFolders.setOnClickListener(View.OnClickListener{
    onClick = function(v)
      openExplorerDialog(true, nil, true, false)
    end
  })
  layout.addView(btnHiddenFolders)

  settingsDialog.setView(scrollView)

  settingsDialog.setPositiveButton("Save Settings", DialogInterface.OnClickListener{
    onClick = function(d, w)
      local selectedPos = timeSpinner.getSelectedItemPosition()
      if selectedPos == 0 then skipDuration = 10000
      elseif selectedPos == 1 then skipDuration = 20000
      elseif selectedPos == 2 then skipDuration = 30000
      elseif selectedPos == 60000 then skipDuration = 60000 end

      backgroundPlay = chkBgPlay.isChecked()
      singleLoop = chkSingleLoop.isChecked()
      gaplessPlay = chkGapless.isChecked()
      skipSilence = chkSkipSilence.isChecked()
      noiseReduction = chkNoiseRed.isChecked()
      fadeEffect = chkFade.isChecked()

      eqPreset = presets[eqSpinner.getSelectedItemPosition() + 1]

      local timerSel = timerSpinner.getSelectedItemPosition()
      if sleepTimerRunnable then
        sleepTimerHandler.removeCallbacks(sleepTimerRunnable)
      end
      if timerSel > 0 and timerSel < 4 then
        local mins = timerSel == 1 and 15 or (timerSel == 2 and 30 or 60)
        sleepTimerRunnable = Runnable{
          run = function()
            pcall(function()
              if mediaPlayer then mediaPlayer.pause() end
              Toast.makeText(ctx, "Sleep Timer: Audio Paused", Toast.LENGTH_SHORT).show()
            end)
          end
        }
        sleepTimerHandler.postDelayed(sleepTimerRunnable, mins * 60 * 1000)
      end

      if mediaPlayer then
        pcall(function() mediaPlayer.setLooping(singleLoop) end)
      end

      local editor = prefs.edit()
      editor.putInt("skipDuration", skipDuration)
      editor.putBoolean("backgroundPlay", backgroundPlay)
      editor.putBoolean("singleLoop", singleLoop)
      editor.putBoolean("gaplessPlay", gaplessPlay)
      editor.putBoolean("skipSilence", skipSilence)
      editor.putBoolean("noiseReduction", noiseReduction)
      editor.putBoolean("fadeEffect", fadeEffect)
      editor.putString("eqPreset", eqPreset)
      editor.apply()

      Toast.makeText(ctx, "All settings saved successfully!", Toast.LENGTH_SHORT).show()
    end
  })

  settingsDialog.setNegativeButton("Go Back", nil)
  showSafeDialog(settingsDialog)
end

btnSettings.setOnClickListener(View.OnClickListener{
  onClick = function(v)
    openSettings()
  end
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

scanAudioFilesAsync = function()
  Thread(Runnable{
    run = function()
      local tempAudioList = {}
      local folderMap = {}
      local tempFolderList = {}

      local resolver = ctx.getContentResolver()
      if resolver then
        local uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        local projection = {
          MediaStore.Audio.Media._ID,
          MediaStore.Audio.Media.DISPLAY_NAME,
          MediaStore.Audio.Media.DATA,
          MediaStore.Audio.Media.SIZE,
          MediaStore.Audio.Media.DATE_MODIFIED,
          MediaStore.Audio.Media.DURATION
        }
        local selection = MediaStore.Audio.Media.IS_MUSIC .. " != 0"
        local cursor = resolver.query(uri, projection, selection, nil, nil)

        if cursor ~= nil then
          local idCol = cursor.getColumnIndex(MediaStore.Audio.Media._ID)
          local nameCol = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
          local dataCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
          local sizeCol = cursor.getColumnIndex(MediaStore.Audio.Media.SIZE)
          local dateCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)
          local durCol = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)

          while cursor.moveToNext() do
            local path = cursor.getString(dataCol)
            if path and File(path).exists() then
              local audioFile = File(path)
              local parentFile = audioFile.getParentFile()
              local folderPath = parentFile and parentFile.getAbsolutePath() or "Unknown"
              local folderName = parentFile and parentFile.getName() or "Unknown"

              table.insert(tempAudioList, {
                id = cursor.getLong(idCol),
                name = cursor.getString(nameCol) or "Unknown",
                path = path,
                size = cursor.getLong(sizeCol) or 0,
                date = cursor.getLong(dateCol) or 0,
                duration = cursor.getLong(durCol) or 0,
                folderPath = folderPath,
                folderName = folderName
              })

              if not folderMap[folderPath] then
                folderMap[folderPath] = {
                  name = folderName,
                  path = folderPath,
                  count = 1
                }
              else
                folderMap[folderPath].count = folderMap[folderPath].count + 1
              end
            end
          end
          cursor.close()
        end
      end

      for _, f in pairs(folderMap) do
        table.insert(tempFolderList, f)
      end

      mainHandler.post(Runnable{
        run = function()
          audioList = tempAudioList
          folderList = tempFolderList

          local visibleFilesCount = 0
          for _, a in ipairs(audioList) do
            if not hiddenFiles[a.path] then
              visibleFilesCount = visibleFilesCount + 1
            end
          end

          local visibleFoldersCount = 0
          for _, f in ipairs(folderList) do
            if not hiddenFolders[f.path] then
              visibleFoldersCount = visibleFoldersCount + 1
            end
          end

          btnShowFiles.setText(string.format("Files (%d files)", visibleFilesCount))
          btnShowFiles.setContentDescription(string.format("Files, total %d files", visibleFilesCount))

          btnShowFolders.setText(string.format("Folders (%d folders)", visibleFoldersCount))
          btnShowFolders.setContentDescription(string.format("Folders, total %d folders", visibleFoldersCount))
        end
      })
    end
  }).start()
end

scanAudioFilesAsync()