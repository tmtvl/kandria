(in-package #:org.shirakumo.fraf.kandria)

(defvar *show-load-screen* NIL)

(defclass progress-bar (alloy:progress)
  ())

(presentations:define-realization (ui progress-bar)
  ((:background simple:rectangle)
   (alloy:margins))
  ((:bar simple:rectangle)
   (alloy:margins 3))
  ((:floruish simple:rectangle)
   (alloy:extent (alloy:pw -0.1) -2 (alloy:pw 1.2) 2)
   :pattern colors:white)
  ((:lab simple:text)
   (alloy:margins 1)
   ""
   :font (setting :display :font)
   :halign :middle
   :valign :middle))

(presentations:define-update (ui progress-bar)
  (:bar
   :pattern colors:white
   :scale (let ((p (/ alloy:value (alloy:maximum alloy:renderable))))
            (alloy:px-size p 1)))
  (:lab
   :text (format NIL "~,1f%" (/ alloy:value (alloy:maximum alloy:renderable) 1/100))
   :pattern colors:accent))

(defclass load-screen-layout (eating-constraint-layout alloy:renderable)
  ())

(presentations:define-realization (ui load-screen-layout)
  ((:bg simple:rectangle)
   (alloy:margins)
   :pattern colors:black))

(defclass load-text (label)
  ())

(presentations:define-realization (ui load-text)
  ((:label simple:text)
   (alloy:margins 0)
   alloy:text
   :font "NotoSansMono"
   :wrap T
   :size (alloy:un 12)
   :halign :start
   :valign :bottom))

(presentations:define-update (ui load-text)
  (:label
   :text alloy:text))

(defclass load-screen (loader alloy:observable-object)
  ((progress :initform 0)
   (cold-boot :accessor cold-boot)
   (last-time :accessor last-time)))

(defclass load-panel (fullscreen-panel)
  ((text :accessor text)))

(defmethod initialize-instance :after ((panel load-panel) &key loader)
  (let ((layout (make-instance 'load-screen-layout))
        (bar (alloy:represent (slot-value loader 'progress) 'progress-bar))
        (text (setf (text panel) (make-instance 'load-text :value ""))))
    (alloy:enter text layout :constraints `((:left 20) (:top 0) (:bottom 100) (:right 20)))
    (alloy:enter bar layout :constraints `((:bottom 50) (:center :w) (:width 500) (:height 30)))
    (alloy:finish-structure panel layout NIL)))

(defmethod trial:commit :after (thing (loader load-screen) &key unload show-screen cold))
(defmethod trial:commit ((area staging-area) (loader load-screen) &key unload show-screen cold)
  (declare (ignore unload))
  (if show-screen
      (let ((*show-load-screen* T))
        (setf (cold-boot loader) cold)
        (setf (slot-value loader 'progress) 0)
        (setf (last-time loader) (get-internal-real-time))
        (show-panel 'load-panel :loader loader)
        (prog1 (call-next-method)
          (hide-panel 'load-panel)))
      (let ((*show-load-screen* NIL))
        (call-next-method))))

(defmethod progress ((loader load-screen) so-far total)
  (when *show-load-screen*
    (let ((prog (* 0.1 (floor (* 1000 (/ so-far total)))))
          (text (if (cold-boot loader) (@ load-screen-new-game) (@ load-screen-load-game))))
      (setf (alloy:value (text (find-panel 'load-panel)))
            (subseq text 0 (floor (* 0.01 prog (length text)))))
      (when (/= prog (slot-value loader 'progress))
        (setf (slot-value loader 'progress) prog)
        (let ((ui (unit 'ui-pass +world+)))
          (ignore-errors (render ui T))
          (blit-to-screen ui)))
      (when (if (cold-boot loader)
                (< (* internal-time-units-per-second 1/60) (- (get-internal-real-time) (last-time loader)))
                (< (* internal-time-units-per-second 1/30) (- (get-internal-real-time) (last-time loader))))
        (setf (last-time loader) (get-internal-real-time))
        (swap-buffers *context*)))))
