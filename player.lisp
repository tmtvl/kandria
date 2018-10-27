(in-package #:org.shirakumo.fraf.leaf)

(define-action movement ())

(define-action dash (movement)
  (key-press (one-of key :left-shift))
  (gamepad-press (one-of button :x)))

(define-action start-jump (movement)
  (key-press (one-of key :space))
  (gamepad-press (one-of button :a)))

(define-action start-climb (movement)
  (key-press (one-of key :left-control))
  (gamepad-press (one-of button :r2 :l2)))

(define-action start-left (movement)
  (key-press (one-of key :a :left))
  (gamepad-move (one-of axis :l-h :dpad-h) (< pos -0.2 old-pos)))

(define-action start-right (movement)
  (key-press (one-of key :d :e :right))
  (gamepad-move (one-of axis :l-h :dpad-h) (< old-pos 0.2 pos)))

(define-action start-up (movement)
  (key-press (one-of key :w :\, :up))
  (gamepad-move (one-of axis :l-v :dpad-v) (< pos -0.2 old-pos)))

(define-action start-down (movement)
  (key-press (one-of key :s :o :down))
  (gamepad-move (one-of axis :l-v :dpad-v) (< old-pos 0.2 pos)))

(define-action end-jump (movement)
  (key-release (one-of key :space))
  (gamepad-release (one-of button :a)))

(define-action end-climb (movement)
  (key-release (one-of key :left-control))
  (gamepad-release (one-of button :r2 :l2)))

(define-action end-left (movement)
  (key-release (one-of key :a :left))
  (gamepad-move (one-of axis :l-h :dpad-h) (< old-pos -0.2 pos)))

(define-action end-right (movement)
  (key-release (one-of key :d :e :right))
  (gamepad-move (one-of axis :l-h :dpad-h) (< pos 0.2 old-pos)))

(define-action end-up (movement)
  (key-release (one-of key :w :\, :up))
  (gamepad-move (one-of axis :l-v :dpad-v) (< old-pos -0.2 pos)))

(define-action end-down (movement)
  (key-release (one-of key :s :o :down))
  (gamepad-move (one-of axis :l-v :dpad-v) (< pos 0.2 old-pos)))

(define-retention movement (ev)
  (typecase ev
    (start-jump (setf (retained 'movement :jump) T))
    (start-climb (setf (retained 'movement :climb) T))
    (start-left (setf (retained 'movement :left) T))
    (start-right (setf (retained 'movement :right) T))
    (start-up (setf (retained 'movement :up) T))
    (start-down (setf (retained 'movement :down) T))
    (end-jump (setf (retained 'movement :jump) NIL))
    (end-climb (setf (retained 'movement :climb) NIL))
    (end-left (setf (retained 'movement :left) NIL))
    (end-right (setf (retained 'movement :right) NIL))
    (end-up (setf (retained 'movement :up) NIL))
    (end-down (setf (retained 'movement :down) NIL))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defclass located-entity (entity)
    ((location :initarg :location :initform (vec 0 0) :accessor location)))

  (defclass facing-entity (entity)
    ((direction :initarg :direction :initform -1 :accessor direction))))

(defmethod paint :around ((obj located-entity) target)
  (with-pushed-matrix ()
    (translate-by (round (vx (location obj))) (round (vy (location obj))) 0)
    (call-next-method)))

(defmethod paint :around ((obj facing-entity) target)
  (with-pushed-matrix ()
    (scale-by (direction obj) 1 1)
    (call-next-method)))

(define-subject moving (located-entity)
  ((velocity :initarg :velocity :accessor velocity)
   (collisions :initform (make-array 4 :element-type 'bit :initial-element 0) :reader collisions)
   (bsize :initarg :bsize :accessor bsize))
  (:default-initargs :velocity (vec 0 0)
                     :bsize (vec *default-tile-size* *default-tile-size*)))

(define-generic-handler (moving tick trial:tick))

(defmethod scan (entity target))

(defun closer (a b dir)
  (< (abs (v. a dir)) (abs (v. b dir))))

(defmethod tick ((moving moving) ev)
  (let* ((scene (scene (handler *context*)))
         (surface (unit :surface scene))
         (loc (location moving))
         (vel (velocity moving))
         (size (bsize moving)))
    ;; Scan for hits until we run out of velocity or hits.
    (fill (collisions moving) 0)
    (loop while (and (or (/= 0 (vx vel)) (/= 0 (vy vel)))
                     (scan surface moving)))
    ;; Remaining velocity (if any) can be added safely.
    (nv+ loc vel)
    ;; Point test for adjacent walls
    (let ((tl (tile (vec (- (vx loc) (/ (vx size) 2) 1) (+ (vy loc) (/ (vy size) 2) -1)) surface))
          (bl (tile (vec (- (vx loc) (/ (vx size) 2) 1) (- (vy loc) (/ (vy size) 2) -1)) surface))
          (tr (tile (vec (+ (vx loc) (/ (vx size) 2) 1) (+ (vy loc) (/ (vy size) 2) -1)) surface))
          (br (tile (vec (+ (vx loc) (/ (vx size) 2) 1) (- (vy loc) (/ (vy size) 2) -1)) surface)))
      (when (or (eql 1 tl) (eql 1 bl)) (setf (bit (collisions moving) 3) 1))
      (when (or (eql 1 tr) (eql 1 br)) (setf (bit (collisions moving) 1) 1)))))

(defmethod collide ((moving moving) (block ground) hit)
  (let* ((loc (location moving))
         (vel (velocity moving))
         (pos (hit-location hit))
         (normal (hit-normal hit))
         (height (/ (vy (bsize moving)) 2))
         (t-s (/ (block-s block) 2)))
    (cond ((= +1 (vy normal)) (setf (bit (collisions moving) 2) 1))
          ((= -1 (vy normal)) (setf (bit (collisions moving) 0) 1))
          ((= +1 (vx normal)) (setf (bit (collisions moving) 3) 1))
          ((= -1 (vx normal)) (setf (bit (collisions moving) 1) 1)))
    (nv+ loc (v* vel (hit-time hit)))
    (nv- vel (v* normal (v. vel normal)))
    ;; Zip out of ground in case of clipping
    (when (and (/= 0 (vy normal))
               (< (vy pos) (vy loc))
               (< (- (vy loc) height)
                  (+ (vy pos) t-s)))
      (setf (vy loc) (+ (vy pos) t-s height)))))

(defmethod collide ((moving moving) (block platform) hit)
  (let* ((loc (location moving))
         (vel (velocity moving))
         (pos (hit-location hit))
         (normal (hit-normal hit))
         (height (/ (vy (bsize moving)) 2))
         (t-s (/ (block-s block) 2)))
    (unless (and (= 1 (vy normal))
                 (<= (vy pos) (- (vy loc) t-s height)))
      (decline))
    (setf (bit (collisions moving) 2) 1)
    (nv+ loc (v* vel (hit-time hit)))
    (nv- vel (v* normal (v. vel normal)))))

(defmethod collide ((moving moving) (block spike) hit)
  (die moving)
  (decline))

(defmethod collide ((moving moving) (block slope) hit)
  (let* ((loc (location moving))
         (vel (velocity moving))
         (pos (hit-location hit))
         (height (/ (vy (bsize moving)) 2))
         (t-s (/ (block-s block) 2))
         (l (slope-l block))
         (r (slope-r block)))
    (decline)
    ;; FIXME: slopes lol
    ))

(define-shader-subject player (animated-sprite-subject moving facing-entity)
  ((status :initform NIL :accessor status)
   (vlim  :initform (vec 10 10) :accessor vlim)
   (vmove :initform (vec2 0.5 0.1) :accessor vmove)
   (vclim :initform (vec2 0.75 1.5) :accessor vclim)
   (vjump :initform (vec4 2 3.5 3 2) :accessor vjump)
   (vdash :initform (vec2 5 0.95) :accessor vdash)
   (jump-count :initform 0 :accessor jump-count)
   (dash-count :initform 0 :accessor dash-count))
  (:default-initargs
   :name :player
   :vertex-array (asset 'leaf 'player-mesh)
   :texture (asset 'leaf 'player)
   :location (vec 32 32)
   :bsize (vec 8 16)
   :size (vec 16 16)
   :animation 0
   :animations '((1.0 4)
                 (0.8 10)
                 (0.5 6 :loop-to 4)
                 (0.5 4 :loop-to 2)
                 (0.5 4)
                 (0.5 5 :loop-to 4)
                 (1.0 1)
                 (1.0 7 :start 33 :loop-to 6))))

(defun update-instance-initforms (class)
  (flet ((update (instance)
           (loop for slot in (c2mop:class-direct-slots class)
                 for name = (c2mop:slot-definition-name slot)
                 for init = (c2mop:slot-definition-initform slot)
                 when init do (setf (slot-value instance name) (eval init)))))
    (when (window :main NIL)
      (for:for ((entity over (scene (window :main))))
        (when (typep entity class)
          (update entity))))))

(define-handler (player dash) (ev)
  (let ((vel (velocity player))
        (vdash (vdash player)))
    (when (= 0 (dash-count player))
      (vsetf vel
             (cond ((retained 'movement :left)  -1)
                   ((retained 'movement :right) +1)
                   (T                            0))
             (cond ((retained 'movement :up)    +1)
                   ((retained 'movement :down)  -1)
                   (T                            0)))
      (setf (status player) :dashing)
      (when (v= 0 vel) (setf (vx vel) 1))
      (nv* vel (/ (vx vdash) (vlength vel))))))

(define-handler (player start-jump) (ev)
  (let ((collisions (collisions player))
        (vel (velocity player))
        (vjump (vjump player)))
    (cond ((bitp collisions 2)
           ;; Ground jump
           (setf (vy vel) (vx vjump))
           (incf (jump-count player))
           (enter (make-instance 'dust-cloud :location (vcopy (location player)))
                  (scene (handler *context*))))
          ((or (bitp collisions 1)
               (bitp collisions 3))
           ;; Wall jump
           (setf (vx vel) (* (if (bitp collisions 1) -1.0 1.0)
                             (vz vjump)))
           (setf (vy vel) (vw vjump))))))

(declaim (inline bitp))
(defun bitp (bitarr bit)
  (= 1 (bit bitarr bit)))

(defmethod collide :before ((player player) (block block) hit)
  (unless (typep block 'spike)
    (when (and (= +1 (vy (hit-normal hit)))
               (< (vy (velocity player)) -2))
      (enter (make-instance 'dust-cloud :location (nv+ (v* (velocity player) (hit-time hit)) (location player)))
             (scene (handler *context*))))))

(defmethod tick :after ((player player) ev)
  (when (bitp (collisions player) 2)
    (setf (jump-count player) 0)
    (when (< 20 (dash-count player))
      (setf (dash-count player) 0))))

(defmethod tick :before ((player player) ev)
  (let ((collisions (collisions player))
        (vel (velocity player))
        (vlim  (vlim  player))
        (vmove (vmove player))
        (vclim (vclim player))
        (vjump (vjump player))
        (vdash (vdash player)))
    (case (status player)
      (:dashing
       (when (< 20 (dash-count player))
         (setf (status player) NIL))
       (incf (dash-count player))
       (nv* vel (vy vdash)))
      (:dying
       (nv* vel 0.9))
      (T
       ;; Animations
       (cond ((and (/= 0 (jump-count player))
                   (retained 'movement :jump))
              (setf (animation player) 2))
             ((and (or (bitp collisions 1)
                       (bitp collisions 3))
                   (retained 'movement :climb))
              (setf (animation player) 4)
              (when (<= (vy vel) 0)
                (setf (frame player) 24)))
             ((bitp collisions 2)
              (setf (animation player) (if (v= 0 vel) 0 1)))
             (T
              (setf (animation player) 3)))
       ;; Movement
       (cond ((and (or (bitp collisions 1)
                       (bitp collisions 3))
                   (retained 'movement :climb)
                   (not (retained 'movement :jump)))
              ;; Climbing
              (cond ((retained 'movement :up)
                     (setf (vy vel) (vx vclim)))
                    ((retained 'movement :down)
                     (setf (vy vel) (* (vy vclim) -1)))
                    (T
                     (setf (vy vel) 0))))
             (T
              ;; Movement (air, ground)
              (cond ((retained 'movement :left)
                     (setf (direction player) -1)
                     (when (< (- (vx vmove)) (vx vel))
                       (decf (vx vel) (vx vmove))))
                    ((retained 'movement :right)
                     (setf (direction player) +1)
                     (when (< (vx vel) (vx vmove))
                       (incf (vx vel) (vx vmove)))))
              (cond ((<= (vx vel) (- (vy vmove)))
                     (incf (vx vel) (vy vmove)))
                    ((<= (vy vmove) (vx vel))
                     (decf (vx vel) (vy vmove)))
                    (T
                     (setf (vx vel) 0)))
              ;; Jump progress
              (when (< 0 (jump-count player))
                (when (and (retained 'movement :jump)
                           (= 15 (jump-count player)))
                  (setf (vy vel) (* (vy vjump) (vy vel))))
                (incf (jump-count player)))
              ;; FIXME: Hard-coded gravity
              (decf (vy vel) 0.1)
              (nvclamp (v- vlim) vel vlim))))))
  ;; OOB
  (when (< (vy (location player)) 0)
    (die player)))

(defmethod enter :after ((player player) (scene scene))
  (add-progression (progression-definition 'intro) scene)
  (add-progression (progression-definition 'revive) scene)
  (add-progression (progression-definition 'die) scene))

(defmethod register-object-for-pass :after (pass (player player))
  (register-object-for-pass pass (find-class 'dust-cloud)))

(defmethod die ((player player))
  (unless (eql (status player) :dying)
    (setf (status player) :dying)
    (setf (animation player) 5)
    (nv* (velocity player) -1)
    (start (reset (progression 'die (scene (handler *context*)))))))

(defmethod death ((player player))
  (start (reset (progression 'revive (scene (handler *context*)))))
  (setf (animation player) 6)
  (setf (vx (location player)) 96)
  (setf (vy (location player)) 32))

(defun player-screen-y ()
  (* (- (vy (location (unit :player T))) (vy (location (unit :camera T))))
     (zoom (unit :camera T))))

(define-progression intro
  0.0 0.1 (:blink (calc middle :to (player-screen-y))
                  (set strength :from 1.0 :to 1.0))
  2.0 4.0 (:blink (set strength :from 1.0 :to 0.9 :ease cubic-in-out))
          (:bokeh (set strength :from 100.0 :to 80.0 :ease cubic-in-out))
  4.0 5.0 (:blink (set strength :to 1.0 :ease cubic-in-out))
  5.0 6.0 (:blink (set strength :to 0.7 :ease cubic-in-out))
  6.0 6.5 (:blink (set strength :to 1.0 :ease cubic-in))
  5.0 7.0 (:bokeh (set strength :to 0.0 :ease circ-in))
  6.5 6.7 (:blink (set strength :to 0.0 :ease cubic-in-out))
  6.7 6.8 (:blink (set strength :to 1.0 :ease cubic-in))
  6.8 6.9 (:blink (set strength :to 0.0 :ease cubic-in))
  6.9 7.0 (:blink (set strength :to 1.0 :ease cubic-in))
  7.0 7.1 (:blink (set strength :to 0.0 :ease cubic-in)))

(define-progression revive
  0.0 1.5 (:blink (calc middle :to (player-screen-y)))
  0.0 0.6 (:blink (set strength :from 1.0 :to 0.3 :ease cubic-in-out))
          (:bokeh (set strength :from 100.0 :to 10.0 :ease cubic-in-out))
  0.4 0.4 (:player (call (lambda (player tt dt) (setf (animation player) 7))))
  0.6 0.8 (:blink (set strength :to 1.0 :ease cubic-in))
          (:bokeh (set strength :to 0.0 :ease cubic-out))
  0.9 1.0 (:blink (set strength :to 0.0 :ease cubic-out))
  1.5 1.5 (:player (call (lambda (player tt dt) (setf (status player) NIL)))))

(define-progression die
  0.0 0.8 (:blink (calc middle :to (player-screen-y)))
  0.0 0.8 (:blink (set strength :from 0.0 :to 1.0 :ease cubic-in))
          (:bokeh (set strength :from 0.0 :to 10.0))
  0.8 0.8 (:player (call (lambda (player tt dt) (death player)))))
