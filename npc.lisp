(in-package #:org.shirakumo.fraf.kandria)

(defclass npc-block-zone (ephemeral resizable sized-entity collider creatable)
  ((name :initform NIL)))

(define-shader-entity npc (inventory ai-entity animatable ephemeral dialog-entity profile)
  ((bsize :initform (vec 8 15))
   (target :initform NIL :accessor target)
   (companion :initform NIL :accessor companion)
   (walk :initform NIL :accessor walk)
   (lead-interrupt :initform "| Where are you going? It's this way!" :accessor lead-interrupt)))

(defmethod print-object ((npc npc) stream)
  (print-unreadable-object (npc stream :type T)
    (format stream "~s ~s" (state npc) (ai-state npc))))

(defmethod capable-p ((npc npc) (edge jump-node)) T)

(defmethod description ((npc npc))
  (language-string 'npc))

(defmethod movement-speed ((npc npc))
  (case (state npc)
    (:crawling (p! crawl))
    (:climbing (p! climb-up))
    (T (if (walk npc)
           (p! slowwalk-limit)
           (p! walk-limit)))))

(defmethod interactable-p ((npc npc))
  (and (eql (state npc) :normal)
       (interactions npc)))

(defmethod base-health ((npc npc))
  1000)

(defmethod hurt ((npc npc) (player player)))
(defmethod collides-p ((npc npc) (enemy enemy) hit) NIL)
(defmethod collides-p ((enemy enemy) (npc npc) hit) NIL)
(defmethod collides-p ((npc npc) (elevator elevator) hit) NIL)
(defmethod die ((npc npc))
  (error "WTF, NPC died for some reason. That shouldn't happen!"))
(defmethod oob ((npc npc) (none null))
  (error "~a fell out of the world." npc))

(defmethod target-blocked-p ((entity located-entity))
  (bvh:do-fitting (entity (bvh (region +world+)) entity)
    (when (typep entity 'npc-block-zone)
      (return T))))

(defmethod target-blocked-p ((location vec2))
  (bvh:do-fitting (entity (bvh (region +world+)) location)
    (when (typep entity 'npc-block-zone)
      (return T))))

(defmethod (setf state) :before (state (npc npc))
  (unless (eq state (state npc))
    (case state
      (:crawling
       (setf (vy (bsize npc)) 7)
       (decf (vy (location npc)) 8)))
    (case (state npc)
      (:crawling
       (incf (vy (location npc)) 8)
       (setf (vy (bsize npc)) 15)))))

(defmethod handle :before ((ev tick) (npc npc))
  (case (state npc)
    (:normal
     (let ((vel (velocity npc)))
       (setf (vy vel) (max (- (p! slowfall-limit)) (vy vel)))))))

(defmethod handle :after ((ev tick) (npc npc))
  (let ((vel (velocity npc))
        (collisions (collisions npc)))
    (setf (playback-direction npc) +1)
    (setf (playback-speed npc) 1.0)
    (case (state npc)
      (:climbing
       (setf (animation npc) 'climb)
       (cond
         ((< (vy vel) 0)
          (setf (playback-direction npc) -1)
          (setf (playback-speed npc) 1.5))
         ((= 0 (vy vel))
          (setf (clock npc) 0.0))))
      (:crawling
       (cond ((< 0 (vx vel))
              (setf (direction npc) +1))
             ((< (vx vel) 0)
              (setf (direction npc) -1)))
       (setf (animation npc) 'crawl)
       (when (= 0 (vx vel))
         (setf (clock npc) 0.0)))
      (:normal
       (cond ((< 0 (vx vel))
              (setf (direction npc) +1))
             ((< (vx vel) 0)
              (setf (direction npc) -1)))
       (cond ((< 0 (vy vel))
              (setf (animation npc) 'jump))
             ((null (svref collisions 2))
              (cond ((< (air-time npc) 0.1))
                    ((typep (svref collisions 1) 'ground)
                     (setf (animation npc) 'fall)
                     (setf (direction npc) +1)
                     (when (< (clock npc) 0.01)
                       (trigger 'slide npc :direction -1)))
                    ((typep (svref collisions 3) 'ground)
                     (setf (animation npc) 'fall)
                     (setf (direction npc) -1)
                     (when (< (clock npc) 0.01)
                       (trigger 'slide npc :direction +1)))
                    (T
                     (ignore-errors
                      (setf (animation npc) 'fall)))))
             ((< (p! slowwalk-limit) (abs (vx vel)))
              (setf (playback-speed npc) (/ (abs (vx vel)) (p! walk-limit)))
              (setf (animation npc) 'run))
             ((< 0 (abs (vx vel)))
              (setf (playback-speed npc) (/ (abs (vx vel)) (p! slowwalk-limit)))
              (setf (animation npc) 'walk))
             ;; KLUDGE: Ugh.
             ((not (eql :sit (ai-state npc)))
              (setf (animation npc) 'stand)))))
    (cond ((eql (name (animation npc)) 'slide)
           (harmony:play (// 'sound 'slide)))
          (T
           (harmony:stop (// 'sound 'slide))))))

(defmethod handle-ai-states ((npc npc) ev)
  (let ((companion (companion npc))
        (min-distance (* 2 +tile-size+))
        (max-distance (* 5 +tile-size+)))
    (case (ai-state npc)
      (:normal
       (when (path npc)
         (execute-path npc ev)))
      (:move-to
       (cond ((path npc)
              (execute-path npc ev))
             ((< (vsqrdistance (location npc) (target npc)) (expt min-distance 2))
              (setf (ai-state npc) :normal))
             (T
              (vsetf (location npc)
                     (vx (target npc))
                     (vy (target npc)))
              (stop-following npc))))
      (:lead
       (let ((distance (vsqrdistance (location npc) (location companion))))
         (flet ((complete ()
                  (setf (companion npc) NIL)
                  (setf (path npc) ())
                  (setf (ai-state npc) :normal)))
           (cond ((and (< (expt (* 20 +tile-size+) 2) distance)
                       (not (eq (chunk npc) (chunk companion))))
                  (setf (ai-state npc) :lead-check))
                 ((< (vsqrdistance (location npc) (target npc)) (expt min-distance 2))
                  (complete))
                 ((null (path npc))
                  (unless (move-to (target npc) npc)
                    (cond ((~= (vx (location npc)) (vx (target npc)) 16)
                           (complete))
                          (T
                           (cerror "Clear the lead" "What the fuck? Don't know how to get to ~a from ~a" (target npc) (location npc))
                           (stop-following npc)))))
                 (T
                  (execute-path npc ev))))))
      (:lead-check
       (let ((distance (vsqrdistance (location npc) (location companion))))
         (cond ((< distance (expt (* 10 +tile-size+) 2))
                (interrupt-walk-n-talk NIL)
                (setf (ai-state npc) :lead))
               ((close-to-path-p (location companion) (path npc) max-distance)
                (interrupt-walk-n-talk NIL)
                (setf (ai-state npc) :lead-teleport))
               (T
                (setf (path npc) NIL)
                (interrupt-walk-n-talk (lead-interrupt npc))))))
      (:lead-teleport
       (setf (path npc) NIL)
       (setf (state npc) :normal)
       (when (svref (collisions companion) 2)
         (vsetf (location npc)
                (vx (location companion))
                (+ (vy (location companion)) 4))
         (if (move-to (target npc) npc)
             (setf (ai-state npc) :lead)
             (setf (ai-state npc) :lead-check))))
      (:follow
       (let ((distance (vsqrdistance (location npc) (location companion))))
         (cond ((< distance (expt max-distance 2))
                (setf (vx (velocity npc)) 0)
                (setf (path npc) NIL))
               ((path npc)
                (execute-path npc ev))
               (T
                (setf (ai-state npc) :follow-check)))))
      (:follow-check
       (let ((distance (vsqrdistance (location npc) (location companion))))
         (cond ((target-blocked-p companion)
                ;; TODO: make it customisable.
                (walk-n-talk (format NIL "~~ ~a
| This doesn't look safe. I'm going to wait here for you, alright?"
                                     (type-of npc)))
                (setf (vx (velocity npc)) 0)
                (setf (ai-state npc) :follow-wait))
               ((< distance (expt (* 3 +tile-size+) 2))
                (setf (ai-state npc) :follow))
               ((and (< (expt (* 40 +tile-size+) 2) distance)
                     (not (eq (chunk npc) (chunk companion))))
                ;; TODO: shout where are you, then timer it.
                (setf (ai-state npc) :follow-teleport))
               ((= 0 (mod (fc ev) 100))
                (when (move-to companion npc)
                  (setf (ai-state npc) :follow))))))
      (:follow-teleport
       ;; TODO: Smart-teleport: search for places just outside view of the companion from
       ;;       which the companion is reachable
       (setf (path npc) NIL)
       (setf (state npc) :normal)
       (when (typep (svref (collisions companion) 2) 'block)
         (vsetf (location npc)
                (vx (location companion))
                (+ (vy (location companion)) 4))
         (setf (ai-state npc) :follow)))
      (:follow-wait
       (let ((distance (vsqrdistance (location npc) (location companion))))
         (when (and (< distance (expt (* 3 +tile-size+) 2))
                    (not (target-blocked-p companion)))
           (setf (ai-state npc) :follow))))
      (:cowering
       (cond ((enemies-present-p (location npc))
              (unless (find (state npc) '(:animated :stunned :dying))
                (start-animation 'cower npc)))
             ((target npc)
              (setf (state npc) :normal)
              (lead (companion npc) (target npc) npc))
             ((companion npc)
              (setf (state npc) :normal)
              (follow (companion npc) npc)))))))

(defmethod hurt :after ((npc npc) (enemy enemy))
  (setf (state npc) :cowering))

(defmethod follow ((target located-entity) (npc npc))
  (setf (walk npc) NIL)
  (setf (path npc) NIL)
  (setf (current-node npc) NIL)
  (setf (companion npc) target)
  (setf (ai-state npc) :follow))

(defmethod stop-following ((npc npc))
  (setf (path npc) NIL)
  (setf (companion npc) NIL)
  (setf (target npc) NIL)
  (setf (ai-state npc) :normal))

(defmethod lead (target (goal located-entity) npc)
  (lead target (vcopy (location goal)) npc))

(defmethod lead ((target located-entity) (goal vec2) (npc npc))
  (setf (walk npc) NIL)
  (setf (path npc) NIL)
  (setf (current-node npc) NIL)
  (setf (target npc) goal)
  (setf (companion npc) target)
  (setf (ai-state npc) :lead))

(defmethod move-to :after ((target vec2) (npc npc))
  (when (eql :normal (ai-state npc))
    (setf (target npc) target)
    (setf (ai-state npc) :move-to)))

(defmethod move :after (kind (npc npc) &key)
  (setf (ai-state npc) :normal))

(defun ensure-nearby (place &rest entities)
  (let* ((place (ensure-unit place))
         (loc (location place))
         (bsize (bsize place)))
    (dolist (entity entities)
      (let ((entity (ensure-unit entity)))
        (unless (nearby-p place entity)
          (place-on-ground entity loc (vx bsize) (vy bsize)))))))

(define-shader-entity roaming-npc (npc)
  ((roam-time :initform (random* 5.0 2.0) :accessor roam-time)))

(defmethod collides-p ((npc roaming-npc) (block stopper) hit) T)

(defmethod minimum-idle-time ((npc roaming-npc)) 5)

(defmethod idleable-p ((npc roaming-npc))
  (and (call-next-method)
       (eq :normal (ai-state npc))))

(defun crowding-level (npc)
  (let* ((crowding-level 0.0)
         (center (vx (location npc)))
         (region (tvec (- center (* +tile-size+ 100))
                       (- (vy (location npc)) 32)
                       (+ center (* +tile-size+ 100))
                       (+ (vy (location npc)) 32))))
    (bvh:do-fitting (entity (bvh (region +world+)) region crowding-level)
      (when (and (not (eq entity npc)) (typep entity 'npc))
        (let* ((dist (- (vx (location entity)) center))
               (gauss (* (/ (* 4 (sqrt (* 2 PI)))) (exp (* -0.5 (/ (* dist dist) 16))))))
          (incf crowding-level gauss))))))

(defun crowd-direction (npc)
  (let* ((direction 0.0)
         (center (vx (location npc)))
         (region (tvec (- center (* +tile-size+ 100))
                       (- (vy (location npc)) 32)
                       (+ center (* +tile-size+ 100))
                       (+ (vy (location npc)) 32))))
    (bvh:do-fitting (entity (bvh (region +world+)) region direction)
      (when (and (not (eq entity npc)) (typep entity 'npc))
        (let* ((dist (- (vx (location entity)) center)))
          (when (<= 0.1 (abs dist))
            (incf direction (* (expt (abs dist) -1.1) (float-sign dist)))))))))

(defmethod handle-ai-states ((npc roaming-npc) ev)
  (when (eql :normal (state npc))
    (let* ((speed (movement-speed npc))
           (avg-time 2.0)
           (dt (dt ev))
           (time (decf (roam-time npc) dt))
           (vel (velocity npc)))
      (flet ((normalize ()
               (setf (roam-time npc) (random* 30 15))
               (cond ((< 0.5 (random 1.0))
                      (setf (ai-state npc) :normal))
                     (T
                      (setf (ai-state npc) :sit)
                      (setf (animation npc) 'sit)))))
        (ecase (ai-state npc)
          (:normal
           (setf (vx vel) 0.0)
           (when (<= time 0.0)
             (let ((level (crowding-level npc)))
               (cond ((<= 0.3 level)
                      (setf (ai-state npc) :crowded)
                      (setf (direction npc) (float-sign (random* 0.0 1.0)))
                      (setf (roam-time npc) (random* (+ 0.5 level) 0.5)))
                     (T
                      (setf (ai-state npc) :lonely)
                      (let ((dir (crowd-direction npc)))
                        (setf (direction npc) (float-sign (if (<= dir 1) (random* 0.0 1.0) dir))))
                      (setf (roam-time npc) (random* avg-time 1.0)))))))
          (:sit
           (setf (animation npc) 'sit)
           (when (<= time 0.0)
             (start-animation 'stand-up npc)
             (setf (ai-state npc) :normal)))
          (:lonely
           (setf (vx vel) (* speed (direction npc)))
           (when (svref (collisions npc) (if (< 0 (direction npc)) 1 3))
             (setf (vx vel) 0))
           (cond ((<= time 0.0)
                  (normalize))
                 ((<= time 0.5)
                  (let ((level (crowding-level npc)))
                    (cond ((<= 0.2 level)
                           (normalize))
                          (T
                           (let ((dir (crowd-direction npc)))
                             (setf (direction npc) (float-sign (if (<= dir 1) (random* 0.0 1.0) dir))))))))))
          (:crowded
           (setf (vx vel) (* speed (direction npc)))
           (when (svref (collisions npc) (if (< 0 (direction npc)) 1 3))
             (setf (vx vel) 0))
           (cond ((<= time 0.0)
                  (normalize)))))))))

(define-unit-resolver-methods (setf lead-interrupt) (thing unit))
(define-unit-resolver-methods (setf walk) (thing unit))
(define-unit-resolver-methods follow (unit unit))
(define-unit-resolver-methods stop-following (unit))
(define-unit-resolver-methods lead (unit unit unit))

(define-shader-entity fi (npc creatable)
  ((name :initform 'fi)
   (profile-sprite-data :initform (asset 'kandria 'fi-profile))
   (nametag :initform (@ fi-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'fi)))

(define-shader-entity catherine (npc creatable)
  ((name :initform 'catherine)
   (profile-sprite-data :initform (asset 'kandria 'catherine-profile))
   (nametag :initform (@ catherine-nametag))
   (lead-interrupt :initform "~ catherine
| (:shout)[? This way. | Follow me. | Keep up. | Let's go.]"))
  (:default-initargs
   :sprite-data (asset 'kandria 'catherine)))

(defmethod movement-speed ((catherine catherine))
  (* 1.01 (call-next-method)))

(defmethod capable-p ((catherine catherine) (edge crawl-node)) T)
(defmethod capable-p ((catherine catherine) (edge climb-node)) T)

(define-shader-entity jack (npc creatable)
  ((name :initform 'jack)
   (profile-sprite-data :initform (asset 'kandria 'jack-profile))
   (nametag :initform (@ jack-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'jack)))

(defmethod movement-speed ((jack jack))
  (* 0.8 (call-next-method)))

(defmethod (setf animation) ((_ (eql 'run)) (jack jack))
  (setf (animation jack) 'walk))
  
(define-shader-entity trader (npc creatable)
  ((name :initform 'trader)
   (profile-sprite-data :initform (asset 'kandria 'sahil-profile))
   (nametag :initform (@ trader-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'sahil)))

(define-shader-entity innis (npc creatable)
  ((name :initform 'innis)
   (profile-sprite-data :initform (asset 'kandria 'innis-profile))
   (nametag :initform (@ innis-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'innis)))
   
(define-shader-entity islay (npc creatable)
  ((name :initform 'islay)
   (profile-sprite-data :initform (asset 'kandria 'islay-profile))
   (nametag :initform (@ islay-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'islay)))
   
(define-shader-entity alex (npc creatable)
  ((name :initform 'alex)
   (profile-sprite-data :initform (asset 'kandria 'alex-profile))
   (nametag :initform (@ alex-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'alex)))

(define-shader-entity zelah (npc creatable)
  ((name :initform 'zelah)
   (profile-sprite-data :initform (asset 'kandria 'jack-profile))
   (nametag :initform (@ zelah-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'jack)))

(define-shader-entity cerebat-trader (npc creatable)
  ((name :initform 'cerebat-trader)
   (profile-sprite-data :initform (asset 'kandria 'sahil-profile))
   (nametag :initform (@ cerebat-trader-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'sahil)))

(define-shader-entity semi-engineer (roaming-npc creatable)
  ((name :initform (generate-name "ENGINEER"))
   (profile-sprite-data :initform (asset 'kandria 'catherine-profile))
   (nametag :initform (@ semi-engineer-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'villager-engineer)))

(define-shader-entity villager-hunter (roaming-npc creatable)
  ((name :initform (generate-name "HUNTER"))
   (profile-sprite-data :initform (asset 'kandria 'catherine-profile))
   (nametag :initform (@ semi-engineer-nametag)))
  (:default-initargs
   :sprite-data (asset 'kandria 'villager-hunter)))

(define-shader-entity villager (paletted-entity roaming-npc creatable)
  ((name :initform (generate-name "VILLAGER"))
   (profile-sprite-data :initform (asset 'kandria 'catherine-profile))
   (nametag :initform (@ villager-nametag))))

(defmethod initialize-instance :before ((villager villager) &key)
  (case (random 2)
    (0
     (setf (slot-value villager 'trial:sprite-data) (asset 'kandria 'villager-male))
     (setf (palette villager) (// 'kandria 'villager-male-palette)))
    (1
     (setf (slot-value villager 'trial:sprite-data) (asset 'kandria 'villager-female))
     (setf (palette villager) (// 'kandria 'villager-female-palette))))
  (setf (palette-index villager) (random 4)))

(defmethod stage :after ((villager villager) (area staging-area))
  (stage (// 'kandria 'villager-male-palette) area)
  (stage (// 'kandria 'villager-female-palette) area)
  (stage (// 'kandria 'villager-male 'vertex-array) area)
  (stage (// 'kandria 'villager-male 'texture) area)
  (stage (// 'kandria 'villager-female 'vertex-array) area)
  (stage (// 'kandria 'villager-female 'texture) area))

(define-random-draw bar
  (villager 1.0)
  (villager-hunter 0.3)
  (semi-engineer 0.2)
  (cerebat-trader 0.1))

(define-shader-entity pet (animatable ephemeral interactable)
  ())

(defmethod handle :before ((ev tick) (npc pet))
  (let ((vel (velocity npc))
        (dt (dt ev)))
    (case (state npc)
      ((:dying :animated :stunned)
       (handle-animation-states npc ev))
      (T
       (nv+ vel (v* (gravity (medium npc)) dt))))
    (nv+ (frame-velocity npc) vel)))

(defmethod handle :after ((ev tick) (npc pet))
  (case (state npc)
    (:normal
     (let ((player (unit 'player T)))
       (case (name (animation npc))
         (sleep
          (when (< (vsqrdistance (location player) (location npc))
                   (expt (* 3 +tile-size+) 2))
            (setf (animation npc) 'wake)))
         (pet)
         (wake
          (when (< (expt (* 4 +tile-size+) 2)
                   (vsqrdistance (location player) (location npc)))
            (setf (animation npc) 'lay))))))))

(defmethod interactable-p ((npc pet))
  (eql 'wake (name (animation npc))))

(defmethod interact ((npc pet) (player player))
  (setf (animation npc) 'pet)
  (start-animation 'pet player))

(define-shader-entity tame-wolf (pet creatable)
  ()
  (:default-initargs
   :sprite-data (asset 'kandria 'wolf)))

;; KLUDGE: add proper idle at some point.
(defmethod idleable-p ((npc tame-wolf)) NIL)
