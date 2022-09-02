(in-package #:org.shirakumo.fraf.kandria)

(define-shader-entity hurtbox (vertex-entity colored-entity sized-entity standalone-shader-entity alloy:layout-element)
  ((vertex-array :initform (// 'kandria '1x))
   (color :initform (vec 1 0 0 0.5))))

(defmethod apply-transforms progn ((hurtbox hurtbox))
  (let ((size (bsize hurtbox)))
    (translate-by (- (vx size)) (- (vy size)) 100)
    (scale-by (* 2 (vx size)) (* 2 (vy size)) 1)))

(defmethod alloy:render :around ((pass ui-pass) (hurtbox hurtbox))
  (with-pushed-matrix ()
    (apply-transforms hurtbox)
    (render hurtbox NIL)))

(defmethod alloy:render ((pass ui-pass) (hurtbox hurtbox)))

(defmethod alloy:suggest-size (size (hurtbox hurtbox)) size)

(defun compute-frame-location (animation frames frame-idx)
  (let ((loc (vec 0 0))
        (vel (vec 0 0))
        (dt 0.01))
    ;; Simulate state updates until the given frame.
    (loop with i = (start animation)
          for tt from 0 by dt
          for frame = (svref frames i)
          for acc = (acceleration frame)
          until (= i frame-idx)
          do (nv* vel (multiplier frame))
             (incf (vx vel) (* dt (vx acc)))
             (incf (vy vel) (* dt (vy acc)))
             (nvclamp (v- (p! velocity-limit)) vel (p! velocity-limit))
             (when (<= (duration frame) tt)
               (incf i)
               (setf tt 0))
             (nv+ loc vel))
    loc))

(defmethod update-hurtbox ((sprite animatable) start end)
  (let ((start (vmin start end))
        (end (vmax start end)))
    (let* ((bsize (nvabs (nv/ (v- end start) 2)))
           (loc (nv- (v+ start bsize) (location sprite))))
      (when (and (< (vx bsize) 0.1) (< (vy bsize) 0.1))
        (setf bsize (vec 0 0))
        (setf loc (vec 0 0)))
      (setf (hurtbox (frame sprite))
            (vec (vx loc) (vy loc) (vx bsize) (vy bsize))))))

(defclass animation-editor (tool alloy:observable-object)
  ((start-pos :initform NIL :accessor start-pos)
   (timeline :initform NIL :accessor timeline)
   (paused-p :initform T :accessor paused-p)
   (hurtbox :initform (make-instance 'hurtbox) :accessor hurtbox)
   (original-location :initform NIL :accessor original-location)))

(defmethod stage :after ((editor animation-editor) (area staging-area))
  (stage (hurtbox editor) area))

(defmethod hide ((tool animation-editor))
  (when (timeline tool)
    (alloy:leave (timeline tool) T))
  (alloy:leave (hurtbox tool) T))

(defmethod label ((tool animation-editor)) "Animations")

(defmethod (setf tool) :after ((tool animation-editor) (editor editor))
  (setf (direction (entity editor)) +1)
  (unless (original-location tool)
    (setf (original-location tool) (vcopy (location (entity editor)))))
  (unless (timeline tool)
    (setf (timeline tool) (make-instance 'timeline :ui (unit 'ui-pass T) :tool tool :entity (entity editor))))
  (unless (alloy:layout-tree (hurtbox tool))
    (alloy:enter (hurtbox tool) (alloy:popups (alloy:layout-tree (unit 'ui-pass T))))))

(define-handler (animation-editor mouse-press) (pos button)
  (when (eql button :right)
    (let ((pos (mouse-world-pos pos)))
      (setf (start-pos animation-editor) pos)
      (update-hurtbox animation-editor pos pos))))

(define-handler (animation-editor mouse-release) (pos button)
  (when (eql button :right)
    (update-hurtbox animation-editor (start-pos animation-editor) (mouse-world-pos pos))
    (setf (start-pos animation-editor) NIL)))

(define-handler (animation-editor mouse-move) (pos)
  (when (start-pos animation-editor)
    (update-hurtbox animation-editor (start-pos animation-editor) (mouse-world-pos pos))))

(defmethod update-hurtbox ((tool animation-editor) start end)
  (let ((hurtbox (update-hurtbox (entity tool) start end)))
    (setf (location (hurtbox tool)) (v+ (vxy hurtbox) (location (entity tool))))
    (setf (bsize (hurtbox tool)) (vzw hurtbox))))

(defmethod handle ((event key-release) (tool animation-editor))
  ;; FIXME: refresh frame representation in editor on change
  (let* ((entity (entity tool))
         (frame (frame entity)))
    (case (key event)
      (:space
       (setf (paused-p tool) (not (paused-p tool))))
      (:delete
       (clear frame))
      ((:a :n :left)
       (decf (frame-idx tool))
       (when (retained :shift)
         (transfer-frame (frame entity) frame)))
      ((:d :p :right)
       (incf (frame-idx tool))
       (when (retained :shift)
         (transfer-frame (frame entity) frame))))))

(defmethod frame-idx ((tool animation-editor))
  (frame-idx (entity tool)))

(defmethod (setf frame-idx) (idx (tool animation-editor))
  (let* ((sprite (entity tool))
         (animation (animation sprite))
         (timeline (timeline tool)))
    (cond ((<= (end animation) idx)
           (setf idx (start animation)))
          ((< idx (start animation))
           (setf idx (1- (end animation)))))
    (when timeline
      (ignore-errors
       (setf (presentations:update-overrides (alloy:index-element (- (frame-idx tool) (start animation)) (frames timeline)))
             ())
       (setf (presentations:update-overrides (alloy:index-element (- idx (start animation)) (frames timeline)))
             `((:background :pattern ,(colored:color 1 1 1 0.25))))))
    (setf (frame-idx sprite) idx)
    (setf (location sprite) (v+ (original-location tool)
                                (compute-frame-location animation (frames sprite) idx)))
    (let ((hurtbox (hurtbox (aref (frames sprite) idx))))
      (setf (location (hurtbox tool)) (v+ (vxy hurtbox) (location sprite)))
      (setf (bsize (hurtbox tool)) (vzw hurtbox)))))

(defmethod handle ((ev tick) (tool animation-editor))
  (unless (paused-p tool)
    (let* ((sprite (entity tool))
           (idx (frame-idx sprite))
           (frame (aref (frames sprite) idx)))
      (incf (clock sprite) (* (playback-speed sprite) (dt ev)))
      (when (<= (duration frame) (clock sprite))
        (decf (clock sprite) (duration frame))
        (incf idx (playback-direction sprite)))
      (setf (frame-idx tool) idx))))

(defmethod applicable-tools append ((_ animated-sprite))
  '(animation-editor))

(defclass animation-chooser (alloy:combo-set)
  ())

(defclass animation-item (alloy:combo-item)
  ())

(defmethod alloy:text ((item animation-item))
  (string (name (alloy:value item))))

(defmethod alloy:combo-item (value (chooser animation-chooser))
  (make-instance 'animation-item :value value))

(defclass animation-properties (alloy:structure)
  ())

(defmethod initialize-instance :after ((structure animation-properties) &key timeline)
  (let* ((animations (animations (entity timeline)))
         (animation (animation (entity timeline)))
         (layout (make-instance 'alloy:horizontal-linear-layout :min-size (alloy:size 100 20)))
         (focus (make-instance 'alloy:focus-list))
         (next (alloy:represent (next-animation animation) 'animation-chooser :value-set animations))
         (loop-to (alloy:represent (loop-to animation) 'alloy:ranged-wheel :range (cons (start animation) (end animation))))
         (cooldown (alloy:represent (cooldown animation) 'alloy:ranged-wheel :range '(0.0 . 2.0) :step 0.1 :grid 0.1)))
    (alloy:observe 'animation timeline
                   (lambda (animation timeline)
                     (setf (alloy:data next) (alloy:place-data (next-animation animation)))
                     (setf (alloy:data loop-to) (alloy:place-data (loop-to animation)))
                     (setf (alloy:data cooldown) (alloy:place-data (cooldown animation)))))
    (alloy:enter-all layout "Loop to" loop-to "Next" next "Cooldown" cooldown)
    (alloy:enter-all focus loop-to next cooldown)
    (alloy:finish-structure structure layout focus)))

(defclass timeline (alloy:window alloy:observable-object)
  ((animation :accessor animation)
   (entity :initarg :entity :accessor entity)
   (tool :initarg :tool :accessor tool)
   (frames :accessor frames))
  (:default-initargs :title "Animations"
                     :extent (alloy:extent 0 30 (alloy:vw 1) 420)
                     :minimizable T
                     :maximizable NIL))

(defmethod initialize-instance :after ((timeline timeline) &key entity tool)
  (let* ((layout (make-instance 'org.shirakumo.alloy.layouts.constraint:layout))
         (focus (make-instance 'alloy:focus-list :focus-parent timeline))
         (animations (animations entity))
         (animation (alloy:represent (slot-value timeline 'animation) 'animation-chooser :value-set animations))
         (frames (make-instance 'alloy:horizontal-linear-layout :cell-margins (alloy:margins) :min-size (alloy:size 100 300)))
         (frames-focus (make-instance 'alloy:focus-list))
         (labels (make-instance 'alloy:vertical-linear-layout :cell-margins (alloy:margins) :elements '("Frame" "Hurtbox" "Offset" "Acceleration" "Multiplier" "Knockback" "Damage" "Stun" "Interruptable" "Invincible" "Cancelable" "Clear Iframes" "Effect")))
         (scroll (make-instance 'alloy:scroll-view :scroll :x :layout frames :focus frames-focus))
         (save (alloy:represent "Save" 'alloy:button))
         (load (alloy:represent "Load" 'alloy:button))
         (toolbar (make-instance 'alloy:horizontal-linear-layout :cell-margins (alloy:margins 1) :min-size (alloy:size 50 20)))
         (props (make-instance 'animation-properties :timeline timeline))
         (speed (alloy:represent (playback-speed entity) 'alloy:wheel :step 0.1))
         (play/pause (alloy:represent "Play" 'alloy:button))
         (step-prev (alloy:represent "<" 'alloy:button))
         (step-next (alloy:represent ">" 'alloy:button)))
    (setf (frames timeline) frames)
    (alloy:enter-all focus animation save load speed step-prev play/pause step-next props scroll)
    (alloy:enter-all toolbar speed step-prev play/pause step-next)
    (alloy:enter animation layout :constraints `((:left 0) (:top 0) (:width 200) (:height 20)))
    (alloy:enter save layout :constraints `((:right-of ,animation 10) (:top 0) (:width 70) (:height 20)))
    (alloy:enter load layout :constraints `((:right-of ,save 10) (:top 0) (:width 70) (:height 20)))
    (alloy:enter toolbar layout :constraints `((:right-of ,save) (:center :x) (:top 0) (:width 300) (:height 20)))
    (alloy:enter props layout :constraints `((:left 0) (:height 30) (:right 0) (:below ,animation 5)))
    (alloy:enter labels layout :constraints `((:left 0) (:bottom 0) (:width 100) (:below ,(alloy:layout-element props) 10)))
    (alloy:enter scroll layout :constraints `((:right-of ,labels 10) (:bottom 0) (:right 0) (:below ,(alloy:layout-element props) 10)))
    (alloy:observe 'animation timeline (lambda (animation timeline)
                                         (setf (animation entity) animation)
                                         (setf (frame-idx tool) (start animation))
                                         (populate-frames frames frames-focus entity tool)))
    (alloy:observe 'paused-p tool (lambda (value tool)
                                    (setf (alloy:value play/pause) (if value "Play" "Pause"))))
    (alloy:on alloy:activate (save)
      (let* ((asset (generator (texture entity)))
             (output (make-pathname :type "tmp" :defaults (input* asset))))
        (with-open-file (stream output :direction :output :if-exists :supersede)
          (write-animation asset stream))
        (rename-file* output (input* asset))))
    (alloy:on alloy:activate (load)
      (let ((asset (generator (texture entity))))
        (reload asset)
        (setf (animation timeline) (animation timeline))))
    (alloy:on alloy:activate (play/pause)
      (setf (paused-p tool) (not (paused-p tool))))
    (alloy:on alloy:activate (step-prev)
      (setf (paused-p tool) T)
      (decf (frame-idx tool)))
    (alloy:on alloy:activate (step-next)
      (setf (paused-p tool) T)
      (incf (frame-idx tool)))
    (setf (animation timeline) (animation entity))
    (alloy:enter layout timeline)))

(defmethod alloy:close ((timeline timeline))
  (setf (tool (editor (tool timeline))) 'browser))

(defun populate-frames (layout focus entity tool)
  (alloy:clear layout)
  (alloy:clear focus)
  (loop for i from (start (animation entity)) below (end (animation entity))
        for frame = (aref (frames entity) i)
        for edit = (make-instance 'frame-edit :idx (1+ i) :frame frame)
        do (alloy:enter edit layout)
           (alloy:enter edit focus)
           (alloy:on alloy:activate ((alloy:representation 'frame-idx edit))
             (setf (frame-idx tool) (1- (alloy:value alloy:observable)))
             (setf (paused-p tool) T))))

(alloy:define-widget frame-edit (alloy:structure)
  ((frame-idx :initarg :idx :representation (alloy:button) :reader frame-idx)
   (frame :initarg :frame :reader frame)))

(defclass frame-layout (alloy:vertical-linear-layout alloy:renderable)
  ())

(presentations:define-realization (ui frame-layout)
  ((:background simple:rectangle)
   (alloy:margins)
   :pattern colors:black))

(defmethod initialize-instance :after ((edit frame-edit) &key)
  (alloy:finish-structure edit (slot-value edit 'layout) (slot-value edit 'focus)))

(defmethod alloy:render ((ui ui) (layout frame-layout))
  (alloy:reset-visibility ui)
  (call-next-method))

(alloy:define-subcomponent (frame-edit hurtbox) ((hurtbox (frame frame-edit)) trial-alloy::vec4))
(alloy:define-subcomponent (frame-edit offset) ((offset (frame frame-edit)) trial-alloy::vec2 :step 1))
(alloy:define-subcomponent (frame-edit acceleration) ((acceleration (frame frame-edit)) trial-alloy::vec2))
(alloy:define-subcomponent (frame-edit multiplier) ((multiplier (frame frame-edit)) trial-alloy::vec2))
(alloy:define-subcomponent (frame-edit knockback) ((knockback (frame frame-edit)) trial-alloy::vec2))
(alloy:define-subcomponent (frame-edit damage) ((damage (frame frame-edit)) alloy:wheel))
(alloy:define-subcomponent (frame-edit stun) ((stun-time (frame frame-edit)) alloy:wheel :step 0.1))
(alloy:define-subcomponent (frame-edit interruptable) ((interruptable-p (frame frame-edit)) alloy:checkbox))
(alloy:define-subcomponent (frame-edit invincible) ((invincible-p (frame frame-edit)) alloy:checkbox))
(alloy:define-subcomponent (frame-edit cancelable) ((cancelable-p (frame frame-edit)) alloy:checkbox))
(alloy:define-subcomponent (frame-edit iframe-clearing) ((iframe-clearing-p (frame frame-edit)) alloy:checkbox))
(alloy:define-subcomponent (frame-edit effect) ((effect (frame frame-edit)) alloy:combo-set :value-set (list* NIL (sort (list-effects) #'string<))))

(alloy:define-subcontainer (frame-edit layout)
    (frame-layout :cell-margins (alloy:margins 1) :min-size (alloy:size 100 20))
  frame-idx hurtbox offset acceleration multiplier knockback damage stun interruptable invincible cancelable iframe-clearing effect)

(alloy:define-subcontainer (frame-edit focus)
    (alloy:focus-list)
  frame-idx hurtbox offset acceleration multiplier knockback damage stun interruptable invincible cancelable iframe-clearing effect)
