;; -*- mode: poly-dialog; -*-
(in-package #:org.shirakumo.fraf.kandria)

;; TODO replace with proper arena boss fight, leashed to this location or in a plausibly-enclosed arena
(define-sequence-quest (kandria q5b-boss)
  :author "Tim White"
  :title "Find the Saboteur"
  :description "Innis wants me to find the Cerebat saboteur responsible for sabotaging their CCTV, and bring them in."
  (:go-to (q5b-boss-loc)
   :title "Find the saboteur in the Semis low-eastern region, along the Cerebat border")
  (:interact (innis :now T)
"~ player
| (:skeptical)Innis, I found the saboteur. I don't think they're a Cerebat.
| (:embarassed)They're quite big. And I don't think they'll come quietly.
~ innis
| (:pleased)Then might I suggest you defend your wee self.
| (:sly)If you survive I'll be happy to hear your report in person.
| (:angry)Now don't interrupt me again unless it's something important.
  ")
  (:complete (q5b-boss-fight)
   :title "Defeat the saboteur robot in the Semis low-eastern region, along the Cerebat border"
   "~ player
| Alright big boy, let's dance.
| (:giggle)You know the robot, right?
  ")
   (:eval
    (when (complete-p (find-task 'q5b-repair-cctv 'q5b-task-cctv-1) (find-task 'q5b-repair-cctv 'q5b-task-cctv-2) (find-task 'q5b-repair-cctv 'q5b-task-cctv-3))
     (activate (find-task 'q5b-repair-cctv 'q5b-task-return-cctv))
     (deactivate (find-task 'q5b-repair-cctv 'q5b-task-reminder)))))