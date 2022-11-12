(asdf:defsystem kandria
  :version "0.3.1"
  :build-operation "deploy-op"
  :build-pathname #+linux "kandria-linux.run"
                  #+darwin "kandria-macos.o"
                  #+win32 "kandria-windows"
                  #+(and bsd (not darwin)) "kandria-bsd.run"
                  #-(or linux bsd win32) "kandria"
  :entry-point "org.shirakumo.fraf.kandria::main"
  :components ((:file "package")
               (:file "toolkit")
               (:file "helpers")
               (:file "palette")
               (:file "sprite-data")
               (:file "tile-data")
               (:file "gradient")
               (:file "auto-fill")
               (:file "serialization")
               (:file "region")
               (:file "actions")
               (:file "surface")
               (:file "lighting")
               (:file "background")
               (:file "environment")
               (:file "assets")
               (:file "quest")
               (:file "language")
               (:file "shadow-map")
               (:file "particle")
               (:file "chunk")
               (:file "effect")
               (:file "interactable")
               (:file "moving-platform")
               (:file "medium")
               (:file "water")
               (:file "grass")
               (:file "moving")
               (:file "move-to")
               (:file "animatable")
               (:file "spawn")
               (:file "inventory")
               (:file "rope")
               (:file "fishing")
               (:file "trigger")
               (:file "stats")
               (:file "player")
               (:file "toys")
               (:file "ai")
               (:file "enemy")
               (:file "npc")
               (:file "critter")
               (:file "cheats")
               (:file "sentinel")
               (:file "world")
               (:file "save-state")
               (:file "camera")
               (:file "main")
               (:file "deploy")
               (:file "effects")
               (:file "displacement")
               (:file "achievements")
               (:module "versions"
                :components ((:file "v0")
                             (:file "binary-v0")
                             (:file "world-v0")
                             (:file "save-v0")))
               (:module "ui"
                :components ((:file "general")
                             (:file "components")
                             (:file "popup")
                             (:file "textbox")
                             (:file "dialog")
                             (:file "walkntalk")
                             (:file "report")
                             (:file "prompt")
                             (:file "diagnostics")
                             (:file "hud")
                             (:file "quick-menu")
                             (:file "map")
                             (:file "menu")
                             (:file "gameover")
                             (:file "save-menu")
                             (:file "options-menu")
                             (:file "main-menu")
                             (:file "credits")
                             (:file "shop")
                             (:file "load-screen")
                             (:file "pause-screen")
                             (:file "end-screen")
                             (:file "wardrobe")
                             (:file "upgrade")
                             (:file "stats")
                             (:file "fast-travel")
                             (:file "cheats")
                             (:file "demo-intro")
                             (:file "save-icon")
                             (:file "speedrun")
                             (:file "startup")
                             (:file "early-end")
                             (:file "gamepad")))
               (:module "editor"
                :components ((:file "history")
                             (:file "tool")
                             (:file "browser")
                             (:file "paint")
                             (:file "line")
                             (:file "rectangle")
                             (:file "freeform")
                             (:file "editor")
                             (:file "toolbar")
                             (:file "chunk")
                             (:file "remesh")
                             (:file "entity")
                             (:file "selector")
                             (:file "creator")
                             (:file "animation")
                             (:file "move-to")
                             (:file "lighting")
                             (:file "drag")
                             (:file "auto-tile")))
               (:module "world/quests"
                :components ((:file "storyline")
                             (:file "epilogue-2")
                             (:file "epilogue")
                             (:file "epilogue-home")
                             (:file "explosion")
                             (:file "q0-find-jack")
                             (:file "q0-settlement-arrive")
                             (:file "q0-surface")
                             (:file "q10a-return-to-fi")
                             (:file "q10-boss")
                             (:file "q10-wraw")
                             (:file "q11a-bomb-recipe")
                             (:file "q11-intro")
                             (:file "q11-recruit-semis")
                             (:file "q12-help-alex")
                             (:file "q13-intro")
                             (:file "q13-planting-bomb")
                             (:file "q14-envoy")
                             (:file "q14a-zelah-gone")
                             (:file "q15-boss")
                             (:file "q15-catherine")
                             (:file "q15-intro")
                             (:file "q15-target-bomb")
                             (:file "q15-unexploded-bomb")
                             (:file "q1-ready")
                             (:file "q1-water")
                             (:file "q2-intro")
                             (:file "q2-seeds")
                             (:file "q3-intro")
                             (:file "q3-new-home")
                             (:file "q4-find-alex")
                             (:file "q4-intro")
                             (:file "q5a-engineers-return")
                             (:file "q5a-rescue-engineers")
                             (:file "q5b-boss")
                             (:file "q5b-investigate-cctv")
                             (:file "q5-intro")
                             (:file "q5-run-errands")
                             (:file "q6-return-to-fi")
                             (:file "q7-my-name")
                             (:file "q8-alex-cerebat")
                             (:file "q8a-bribe-trader")
                             (:file "q8-meet-council")
                             (:file "q9-contact-fi")
                             (:file "semi-station-marker")
                             (:file "sq1-leaks")
                             (:file "sq2-mushrooms")
                             (:file "sq3-race")
                             (:file "sq4-analyse-robots")
                             (:file "sq4-boss")
                             (:file "sq4-intro")
                             (:file "sq5-intro")
                             (:file "sq5-race")
                             (:file "sq6-deliver-letter")
                             (:file "sq6-intro")
                             (:file "sq7-intro")
                             (:file "sq7-wind-parts")
                             (:file "sq7a-catherine-semis")
                             (:file "sq8-intro")
                             (:file "sq8-find-council")
                             (:file "sq8-item")
                             (:file "sq9-intro")
                             (:file "sq9-race")
                             (:file "sq10-intro")
                             (:file "sq10-race")
                             (:file "sq11-intro")
                             (:file "sq11-sabotage-station")
                             (:file "sq14-intro")
                             (:file "sq14a-synthesis")
                             (:file "sq14b-boss")
                             (:file "sq14b-synthesis")
                             (:file "sq14c-synthesis")
                             (:file "sq-act1-intro")
                             (:file "trader-arrive")
                             (:file "trader-cerebat")
                             (:file "trader-islay")
                             (:file "tutorial")
                             (:file "world-engineers-wall")
                             (:file "world")
                             (:file "world-move-engineers"))))
  :serial T
  :defsystem-depends-on (:deploy)
  :depends-on (:trial-glfw
               :trial-alloy
               :trial-harmony
               :trial-steam
               :trial-notify
               :trial-feedback
               :trial-png
               :alloy-constraint
               :depot
               :depot-zip
               :zip
               :fast-io
               :ieee-floats
               :babel
               :form-fiddle
               :array-utils
               :lambda-fiddle
               :trivial-arguments
               :trivial-indent
               :speechless
               :kandria-quest
               :alexandria
               :random-state
               :file-select
               :cl-mixed-wav
               :cl-mixed-vorbis
               :zpng
               :jsown
               :swank
               :action-list
               :easing))
