(in-package #:org.shirakumo.fraf.kandria)

(define-shader-entity stamina-wheel (vertex-entity standalone-shader-entity)
  ((vertex-array :initform (// 'kandria '16x))
   (visibility :initform 0.0 :accessor visibility)))

(defmethod render :before ((stamina-wheel stamina-wheel) (program shader-program))
  (let ((player (unit 'player +world+)))
    (translate-by (vx (location player)) (vy (location player)) 10000)
    (scale-by -0.8 0.8 1)
    (translate-by (* -20 (direction player)) 20 0)
    (setf (uniform program "stamina") (max 0.0 (float (/ (climb-strength player) (p! climb-strength)) 0f0)))
    (setf (uniform program "visibility") (clamp 0.0 (visibility stamina-wheel) 1.0))))

(define-class-shader (stamina-wheel :vertex-shader)
  "layout (location = 1) in vec2 vertex_uv;
out vec2 uv;

void main(){ uv = vertex_uv; }")

(define-class-shader (stamina-wheel :fragment-shader)
  "
#define PI 3.141592653589793
in vec2 uv;
out vec4 color;
uniform float stamina;
uniform float visibility;

vec2 rotate(vec2 p, float angle){
  float sine = sin(angle);
  float cosine = cos(angle);
  return vec2(cosine * p.x + sine * p.y, cosine * p.y - sine * p.x);
}

float sdPie(in vec2 p, in float gap, in float rot, in float r){
  p = rotate(p, rot);
  vec2 c = vec2(sin(gap), cos(gap));
  p.x = abs(p.x);
  float l = length(p) - r;
  float m = length(p-c*clamp(dot(p,c),0.0,r));
  return max(l,m*sign(c.y*p.x-c.x*p.y));
}

float sdCirc(in vec2 p, in float r){
  return length(p)-r;
}

vec4 evalSDF(in float sdf, in vec4 color){
  float dsdf = fwidth(sdf) * 0.5;
  return color * smoothstep(dsdf, -dsdf, sdf);
}

vec4 add(vec4 a, vec4 b){
   return mix(a, b, b.a);
}

void main(){
  float b = stamina*PI;
  vec2 p = uv-0.5;
  float inner = -sdCirc(p, 0.225);
  color = evalSDF(sdCirc(p, 0.5), vec4(0,0,0,0.5));
  vec4 c = mix(vec4(1.0, 0, 0, 1), vec4(0.0,0.6,1.0,1), clamp(stamina*2-0.1, 0, 1));
  if(stamina >= 0.9) c = vec4(1);
  color = add(color, evalSDF(max(sdPie(p, b, b, 0.45), inner), c));
  c = mix(vec4(1), vec4(0, 0, 0, 1), (sin(stamina*50))*0.5);
  color = add(color, evalSDF(max(sdPie(p, 0.1, b*2, 0.45), inner), c));
  color *= visibility;
}")

(define-shader-entity player (alloy:observable stats-entity paletted-entity animatable profile ephemeral inventory)
  ((name :initform 'player)
   (palette :initform (// 'kandria 'player-palette))
   (bsize :initform (vec 7.0 15.0))
   (spawn-location :initform (vec2 0 0) :accessor spawn-location)
   (interactable :initform NIL :accessor interactable)
   (jump-time :initform 1.0 :accessor jump-time)
   (dash-time :initform 1.0 :accessor dash-time)
   (run-time :initform 1.0 :accessor run-time)
   (limp-time :initform 0.0 :accessor limp-time)
   (look-time :initform 0.0 :accessor look-time)
   (slide-time :initform 0.0 :accessor slide-time)
   (climb-strength :initform 5.0 :accessor climb-strength)
   (combat-time :initform 10000.0 :accessor combat-time)
   (attack-held :initform NIL :accessor attack-held)
   (used-aerial :initform NIL :accessor used-aerial)
   (buffer :initform (cons NIL 0))
   (prompt :initform (make-instance 'prompt) :reader prompt)
   (prompt-b :initform (make-instance 'prompt) :reader prompt-b)
   (profile-sprite-data :initform (asset 'kandria 'player-profile))
   (nametag :initform (@ player-nametag))
   (invincible :initform (setting :gameplay :god-mode))
   (dash-exhausted :initform NIL :accessor dash-exhausted)
   (trace :initform (make-array (* 12 60 60 2) :element-type 'single-float :adjustable T :fill-pointer 0)
          :accessor movement-trace)
   (fishing-line :initform (make-instance 'fishing-line) :accessor fishing-line)
   (stamina-wheel :initform (make-instance 'stamina-wheel) :accessor stamina-wheel)
   (color :initform (vec 1 1 1 0) :accessor color))
  (:default-initargs
   :sprite-data (asset 'kandria 'player)))

(defmethod initialize-instance :after ((player player) &key)
  (dotimes (i 5) (store 'item:small-health-pack player))
  (dotimes (i 2) (store 'item:medium-health-pack player))
  (setf (active-p (action-set 'in-game)) T)
  (setf (spawn-location player) (vcopy (location player))))

(defmethod register :after ((player player) (world scene))
  (show-panel 'hud))

(defmethod deregister :after ((player player) (world scene))
  (hide-panel 'hud))

(defmethod minimum-idle-time ((player player)) 30)

(defmethod maximum-health ((player player)) 100)

(defmethod resize ((player player) w h))

(defmethod capable-p ((player player) (edge jump-node)) T)
(defmethod capable-p ((player player) (edge crawl-node)) T)
(defmethod capable-p ((player player) (edge climb-node)) T)

(defmethod movement-speed ((player player))
  (case (state player)
    (:crawling (p! crawl))
    (:climbing (p! climb-up))
    (T (p! walk-limit))))

(defmethod stage :after ((player player) (area staging-area))
  (dolist (sound '(player-dash player-jump player-evade player-die player-die-platforming
                   player-low-health player-awaken player-damage enter-water
                   player-red-flashing zombie-die ; Used for explosion
                   player-hard-land player-roll-land
                   player-pick-up player-enter-passage player-soft-land player-wall-slide
                   step-dirt-1 step-dirt-2 step-dirt-3 step-dirt-4
                   step-rocks-1 step-rocks-2 step-rocks-3 step-rocks-4
                   step-sand-1 step-sand-2 step-sand-3 step-sand-4
                   step-metal-1 step-metal-2 step-metal-3 step-metal-4
                   step-concrete-1 step-concrete-2 step-concrete-3 step-concrete-4
                   step-tall-grass-1 step-tall-grass-2 step-tall-grass-3 step-tall-grass-4
                   sword-small-slash-1 sword-small-slash-2 sword-small-slash-3 sword-big-slash
                   sword-hit-ground-soft sword-hit-ground-hard sword-jab
                   sword-rotating-swing-1 sword-rotating-swing-2))
    (stage (// 'sound sound) area))
  (stage (fishing-line player) area)
  (stage (stamina-wheel player) area)
  (stage (// 'kandria 'line-part) area)
  (stage (// 'kandria 'sting) area))

(defun interrupt-movement-trace (player)
  (vector-push-extend (float-features:bits-single-float #b01111111110000000000000000000000) (movement-trace player))
  (vector-push-extend (float-features:bits-single-float #b01111111110000000000000000000000) (movement-trace player)))

(defmethod hurt :after (thing (player player))
  (let ((dir (nv- (vxy (hurtbox player)) (location thing))))
    (trigger (make-instance 'sting-effect :angle (if (v/= 0 dir) (point-angle dir) 0)) player)))

(defmethod (setf medium) :before ((medium medium) (player player))
  (when (or (and (typep (medium player) 'water)
                 (not (typep medium 'water)))
            (and (not (typep (medium player) 'water))
                 (typep medium 'water)))
    (harmony:play (// 'sound 'enter-water))))

(defmethod handle ((ev interact) (player player))
  (let ((interactable (interactable player)))
    (when interactable
      (discard-events +world+)
      (setf (buffer player) NIL)
      (interact interactable player))))

(defmethod interact :before ((thing dialog-entity) (player player))
  (setf (state player) :normal)
  (hide (prompt player)))

(defmethod interact :after ((thing item) (player player))
  (start-animation 'pickup player))

(defmethod interact ((door door) (player player))
  (setf (animation door) 'open)
  (let ((location (location (target door))))
    (start-animation (if (facing-towards-screen-p door) 'enter 'enter-forward) player)
    (transition
      (start-animation 'exit player)
      (setf (animation (target door)) 'open)
      (setf (air-time player) 0.0)
      (setf (buffer player) NIL)
      (setf (location player) (vec (vx location) (- (vy location) 5)))
      (issue +world+ 'force-lighting)
      (snap-to-target (unit :camera T) player))))

(defmethod interact ((trigger teleport-trigger) (player player))
  (when (primary trigger)
    (let ((location (location (target trigger))))
      (vsetf (velocity player) 0 0)
      (transition
        (interrupt-movement-trace player)
        (setf (location player) location)
        (issue +world+ 'force-lighting)
        (clear-retained)
        (snap-to-target (unit :camera T) player)))))

(defmethod interact ((save-point save-point) (player player))
  (setf (vx (location player))
        (- (vx (location save-point)) 11))
  (setf (direction player) +1)
  (start-animation 'phone player)
  (setf (animation save-point) 'call)
  (save-state +main+ T)
  (status #@game-save-complete))

(defmethod enter :after ((player player) (water water))
  (setf (dash-exhausted player) NIL))

(defmethod handle :after ((ev quickmenu) (player player))
  (unless (path player)
    (toggle-panel 'quick-menu)))

(defun handle-evasion (player)
  (let ((endangering (endangering player)))
    (when endangering
      (setf (combat-time player) 0.0)
      (let ((dir (float-sign (- (vx (location endangering)) (vx (location player))))))
        (setf (direction player) dir)
        (start-animation 'evade-left player))
      T)))

(defmethod handle ((ev dash) (player player))
  (setf (limp-time player) (min (limp-time player) 1.0))
  (unless (path player)
    (case (state player)
      (:crawling
       (handle (make-instance 'crawl) player))
      ((:normal :climbing :sliding)
       (let ((vel (velocity player)))
         (cond ((handle-evasion player))
               ((null (dash-exhausted player))
                (setf (dash-time player) 0.0)
                (when (not (or (setting :gameplay :infinite-dash)
                               (typep (medium player) 'water)))
                  (setf (dash-exhausted player) T))
                (vsetf vel
                       (cond ((retained 'left)  -0.5)
                             ((retained 'right) +0.5)
                             (T                    0))
                       (cond ((retained 'up)    +0.5)
                             ((retained 'down)  -0.5)
                             (T                    0)))
                (when (and (eql :climbing (state player))
                           (v= 0 vel))
                  (setf (direction player) (- (direction player))))
                (if (= (vx vel) 0.0)
                    (if (= (vy vel) 0.0)
                        (setf (vx vel) (direction player)))
                    (setf (direction player) (float-sign (vx vel))))
                (nvunit vel)
                (when (and (retained 'jump)
                           (svref (collisions player) 2))
                  (incf (vx vel) (* (direction player) (vx (p! hyperdash-bonus))))
                  (incf (vy vel) (vy (p! hyperdash-bonus))))
                (rumble :duration 0.2 :intensity 0.5)
                (setf (state player) :dashing)
                (if (svref (collisions player) 2)
                    (trigger 'dash player)
                    (trigger 'air-dash player))
                (setf (animation player) 'dash)))))
      (:animated
       ;; Queue dash //except// for when we're being hit, as it's
       ;; unlikely the player will want to dash right after getting
       ;; hit.
       (let ((name (name (animation player))))
         (unless (or (eq name 'light-hit)
                     (eq name 'hard-hit))
           (setf (buffer player) 'dash)))))))

(defmethod handle ((ev jump) (player player))
  (cond ((path player))
        ((eql :animated (state player))
         (setf (buffer player) 'jump))
        ((and (typep (svref (collisions player) 2) 'platform)
              (retained 'down))
         (decf (vy (location player)) 2))
        ((eql :crawling (state player))
         (handle (make-instance 'crawl) player))
        (T
         (setf (jump-time player) (- (p! coyote-time))))))

(defmethod handle ((ev crawl) (player player))
  (unless (path player)
    (case (state player)
      (:normal
       (when (svref (collisions player) 2)
         (setf (state player) :crawling))))))

(defmethod handle ((ev light-attack) (player player))
  (cond ((path player))
        ((eql :animated (state player))
         (setf (buffer player) 'light-attack))
        ((eql :crawling (state player))
         (handle (make-instance 'crawl) player))
        ((and (null (svref (collisions player) 2))
              (used-aerial player)))
        (T
         (setf (attack-held player) T)
         (setf (vw (color player)) 0.0)
         (setf (buffer player) 'light-attack)
         (setf (animation player) 'stand)
         (setf (state player) :animated))))

(defmethod handle ((ev heavy-attack) (player player))
  (cond ((path player))
        ((eql :animated (state player))
         (setf (buffer player) 'heavy-attack))
        ((eql :crawling (state player))
         (handle (make-instance 'crawl) player))
        ((and (null (svref (collisions player) 2))
              (used-aerial player)))
        (T
         (setf (attack-held player) T)
         (setf (vw (color player)) 0.0)
         (setf (buffer player) 'heavy-attack)
         (setf (animation player) 'stand)
         (setf (state player) :animated))))

#-kandria-release
(let ((type (copy-seq '(zombie wolf box drone ball dummy))))
  (defmethod handle ((ev mouse-scroll) (player player))
    (setf type (cycle-list type))
    (status :note "Switched to spawning ~a" (first type)))
  
  (defmethod handle ((ev mouse-release) (player player))
    (when (eql :middle (button ev))
      (spawn (mouse-world-pos (pos ev)) (first type)))))

(flet ((handle-solid (player hit)
         (when (< 0 (vy (hit-normal hit)))
           (cond ((and (< (vy (velocity player)) -6)
                       (< 1.0 (air-time player))
                       (not (eql :animated (state player))))
                  (trigger 'land player :location (nv+ (v* (velocity player) (hit-time hit))
                                                       (location player)))
                  (cond ((or (retained 'left) (retained 'right))
                         (start-animation 'roll player)
                         (harmony:play (// 'sound 'player-roll-land)))
                        (T
                         (start-animation 'land player)
                         (harmony:play (// 'sound 'player-hard-land))))
                  (duck-camera (vx (velocity player)) (vy (velocity player)))
                  (shake-camera :intensity (* 3 (/ (abs (vy (velocity player))) (vy (p! velocity-limit))))))
                 ((and (< (vy (velocity player)) -0.5)
                       (< 0.2 (air-time player)))
                  (harmony:play (// 'sound 'player-soft-land))))
           (unless (eql :dashing (state player))
             (setf (dash-exhausted player) NIL))
           (setf (used-aerial player) NIL))))
  (defmethod collide :before ((player player) (block block) hit)
    (unless (typep block 'spike)
      (handle-solid player hit)))

  (defmethod collide :before ((player player) (solid solid) hit)
    (handle-solid player hit)))

(defmethod collide ((player player) (trigger trigger) hit)
  (when (active-p trigger)
    (interact trigger player)))

(defmethod collides-p ((player player) (block platform) hit)
  (and (call-next-method)
       (not (typep (interactable player) 'elevator))
       (or (not (typep (interactable player) 'rope))
           (not (eq :climbing (state player))))
       (not (and (retained 'down)
                 (retained 'jump)
                 (< 0.01 (air-time player))))))

(defmethod idleable-p ((player player))
  (and (call-next-method)
       (not (or (retained 'up)
                (retained 'down)))))

(defmethod (setf state) :before (state (player player))
  (unless (eq state (state player))
    (let ((bottom (- (vy (location player)) (vy (bsize player)))))
      (case state
        (:normal
         (setf (vw (color player)) 0.0))
        (:crawling
         (setf (vy (bsize player)) 7)
         (setf (vy (location player)) (+ bottom (vy (bsize player))))))
      (case (state player)
        (:crawling
         (setf (vy (bsize player)) 15)
         (setf (vy (location player)) (+ bottom (vy (bsize player)))))))))

(defmethod (setf buffer) (thing (player player))
  (let ((buffer (slot-value player 'buffer)))
    (setf (cdr buffer) (clock +world+))
    (setf (car buffer) thing)))

(defmethod buffer ((player player))
  (let ((buffer (slot-value player 'buffer)))
    (when (< (clock +world+) (+ (cdr buffer) (p! buffer-expiration-time)))
      (car buffer))))

(defun attack-chain-p (input player)
  (case input
    (light-attack
     (case (name (animation player))
       ((light-ground-1 light-ground-2 light-aerial-1 light-aerial-2) T)
       (T NIL)))
    (heavy-attack
     (case (name (animation player))
       ((heavy-ground-1 heavy-ground-2 heavy-aerial-1 heavy-aerial-2) T)
       (T NIL)))))

(defmethod collides-p :around ((player player) thing hit)
  (unless (eql :noclip (state player))
    (call-next-method)))

(defmethod handle :before ((ev tick) (player player))
  (when (path player)
    (execute-path player ev)
    (nv+ (frame-velocity player) (velocity player))
    (return-from handle))
  ;; FIXME: Very bad! We cannot track time passage by frame count!
  ;;        Need to do proper test to check whether a second has passed.
  (when (and (= (mod (fc ev) 60) 0)
             (chunk player)
             (visible-on-map-p (chunk player)))
    (let ((trace (movement-trace player)))
      (declare (type (array single-float (*))))
      (vector-push-extend (vx (location player)) trace)
      (vector-push-extend (vy (location player)) trace)))
  (when (<= (p! climb-strength) (climb-strength player))
    (decf (visibility (stamina-wheel player)) (dt ev)))
  (let* ((collisions (collisions player))
         (dt (dt ev))
         (loc (location player))
         (vel (velocity player))
         (size (bsize player))
         (ground (svref collisions 2))
         (ground-limit (cond ((and (< (p! run-time) (run-time player))
                                   (or (eql :keyboard +input-source+)
                                       (< 0.75 (abs (gamepad:axis :l-h +input-source+)))
                                       (< 0.75 (abs (gamepad:axis :dpad-h +input-source+)))))
                              (p! run-limit))
                             ((or (eql :keyboard +input-source+)
                                  (< 0.75 (abs (gamepad:axis :l-h +input-source+)))
                                  (< 0.75 (abs (gamepad:axis :dpad-h +input-source+))))
                              (p! walk-limit))
                             (T
                              (p! slowwalk-limit))))
         (ground-acc (if (< (p! run-time) (run-time player))
                         (p! run-acc)
                         (p! walk-acc))))
    ;; Advance clocks
    (when (< (abs (vx vel)) (/ (p! walk-limit) 2))
      (setf (run-time player) 0.0))
    (incf (run-time player) dt)
    (incf (combat-time player) dt)
    ;; HUD
    (cond ((< (combat-time player) 5)
           (setf (intended-zoom (unit :camera T))
                 (if (eql 'evade-left (name (animation player)))
                     1.6 1.2))
           (setf (timeout (health (find-panel 'hud))) 5.0))
          ((and (< 5 (combat-time player) 6)
                (< 1 (intended-zoom (unit :camera T))))
           (setf (intended-zoom (unit :camera T)) 1.0)))
    ;; Interaction checks
    (setf (interactable player) NIL)
    (when (and ground (interactable-p ground))
      (setf (interactable player) ground))
    (let ((interactable (tvec (vx2 loc) (vy2 loc) 16 16))
          (trigger (tvec (vx2 loc) (vy2 loc) 16 8)))
      (bvh:do-fitting (entity (bvh (region +world+)) (or (chunk player) player))
        (typecase entity
          (rope
           (when (and (contained-p interactable entity)
                      (< (+ 2 (- (vy loc) (vy size)))
                         (+ (vy (location entity)) (vy (bsize entity)))))
             (setf (interactable player) entity)))
          (interactable
           (when (and (contained-p interactable entity)
                      (interactable-p entity))
             (setf (interactable player) entity)))
          (trigger
           (when (contained-p trigger entity)
             (interact entity player))))))
    (if (and (interactable player)
             (interactable-p (interactable player))
             (eql :normal (state player))
             (setting :gameplay :display-hud))
        (let ((loc (vec (vx (location (interactable player)))
                        (+ (vy loc) (vy (bsize player))))))
          (show (prompt player)
                :button (action (interactable player))
                :location loc
                :description (description (interactable player))))
        (when (slot-boundp (prompt player) 'alloy:layout-parent)
          (hide (prompt player))))
    ;; Handle states.
    (ecase (state player)
      (:noclip
       (setf (animation player) 't-pose)
       (vsetf vel 0 0)
       (when (retained 'left) (setf (vx vel) (- (vx (p! velocity-limit)))))
       (when (retained 'right) (setf (vx vel) (+ (vx (p! velocity-limit)))))
       (when (retained 'up) (setf (vy vel) (+ (vx (p! velocity-limit)))))
       (when (retained 'down) (setf (vy vel) (- (vx (p! velocity-limit))))))
      (:oob
       (vsetf vel 0 0))
      ((:dying :stunned :respawning)
       (handle-animation-states player ev)
       (when (and (cancelable-p (frame player))
                  (or (retained 'left)
                      (retained 'right)))
         (setf (state player) :normal)))
      (:fishing
       (let* ((line (fishing-line player))
              (visible (slot-boundp line 'container)))
         (when visible
           (v<- (location line) (hurtbox player))
           (duck-camera (+ 32 (- (vx (location (buoy line))) (vx loc)))
                        (+ 32 (- (vy (location (buoy line))) (vy loc)))))
         (case (name (animation player))
           (fishing-start
            (if (= (frame-idx player) 543)
                (unless visible
                  (v<- (location line) (hurtbox player))
                  (enter* line (region +world+))))))
         (case (name (animation player))
           (fishing-loop
            (let* ((loc (vcopy (location (buoy line))))
                   (bloc (tvec (+ (vx loc) -10)
                               (+ (vy loc) 16)))
                   (tt (* 1.3 (tt ev)))
                   (t2 (+ tt (/ PI 3))))
              (nv+ loc (vec (* 5 (cos tt)) (* 3 (sin tt) (cos tt))))
              (nv+ bloc (vec (* 5 (cos t2)) (* 3 (sin t2) (cos t2))))
              (show (prompt player) :button 'reel-in
                                    :description (language-string 'reel-in)
                                    :location loc)
              (show (prompt-b player) :button 'stop-fishing
                                      :description (language-string 'stop-fishing)
                                      :location bloc)))
           ((show stand)
            (let* ((loc (tv+ #.(vec 0 16) (location player)))
                   (bloc (tvec (+ (vx loc) -10)
                               (+ (vy loc) 16)))
                   (tt (* 1.3 (tt ev)))
                   (t2 (+ tt (/ PI 3))))
              (nv+ loc (vec (* 5 (cos tt)) (* 3 (sin tt) (cos tt))))
              (nv+ bloc (vec (* 5 (cos t2)) (* 3 (sin t2) (cos t2))))
              (show (prompt player) :button 'cast-line
                                    :description (language-string 'cast-line)
                                    :location loc)
              (show (prompt-b player) :button 'stop-fishing
                                      :description (language-string 'stop-fishing)
                                      :location bloc)))
           (T
            (hide (prompt player))
            (hide (prompt-b player))))))
      (:animated
       (when (and ground (eql 'heavy-aerial-3 (name (animation player))))
         (start-animation 'heavy-aerial-3-release player))
       (let ((buffer (buffer player))
             (animation (animation player)))
         (cond ((and buffer
                     (cancelable-p (frame player))
                     (or (<= (cooldown-time player) 0.0)
                         (eql 'dash buffer)
                         (and (< 3 (- (frame-idx player) (start animation)))
                              (attack-chain-p buffer player))))
                (setf (buffer player) NIL)
                (cond ((retained 'left) (setf (direction player) -1))
                      ((retained 'right) (setf (direction player) +1)))
                (when (or (eql buffer 'light-attack)
                          (eql buffer 'heavy-attack))
                  (setf (combat-time player) 0f0))
                (case buffer
                  (light-attack
                   (case (name animation)
                     (light-ground-1 (start-animation 'light-ground-2 player))
                     (light-ground-2 (start-animation 'light-ground-3 player))
                     (light-aerial-1 (start-animation 'light-aerial-2 player))
                     (light-aerial-2 (start-animation 'light-aerial-3 player))
                     ((evade-left evade-right) (start-animation 'light-counter player))
                     (T
                      (cond ((not (svref (collisions player) 2))
                             (unless (used-aerial player)
                               (setf (used-aerial player) T)
                               (if (retained 'down)
                                   (start-animation 'light-aerial-down player)
                                   (start-animation 'light-aerial-1 player))))
                            ((retained 'up)
                             (start-animation 'light-up player))
                            ((retained 'down)
                             (start-animation 'light-down player))
                            (T
                             (start-animation 'light-ground-1 player))))))
                  (heavy-attack
                   (case (name animation)
                     (heavy-ground-1 (start-animation 'heavy-ground-2 player))
                     (heavy-ground-2 (start-animation 'heavy-ground-3 player))
                     (heavy-aerial-1 (start-animation 'heavy-aerial-2 player))
                     (heavy-aerial-2 (start-animation 'heavy-aerial-3 player))
                     ((evade-left evade-right) (start-animation 'heavy-counter player))
                     (T
                      (cond ((not (svref (collisions player) 2))
                             (unless (used-aerial player)
                               (setf (used-aerial player) T)
                               (if (retained 'down)
                                   (start-animation 'heavy-aerial-3 player)
                                   (start-animation 'heavy-aerial-1 player))))
                            ((retained 'up)
                             (start-animation 'heavy-up player))
                            ((retained 'down)
                             (start-animation 'heavy-down player))
                            (T
                             (start-animation 'heavy-ground-1 player))))))
                  (dash
                   (setf (state player) :normal)
                   (handle (make-instance 'dash) player))
                  (jump
                   (setf (state player) :normal)
                   (handle (make-instance 'jump) player))))
               ((not (retained (case (name animation)
                                 ((light-ground-1 light-charge-2) 'light-attack)
                                 ((heavy-ground-1 heavy-charge-2) 'heavy-attack))))
                (setf (attack-held player) NIL))
               ((and (attack-held player)
                     (<= 2 (- (frame-idx player) (start animation)))
                     (<= (duration (frame player)) (+ dt (clock player))))
                (case (name animation)
                  (light-ground-1
                   (start-animation 'light-charge-2 player))
                  (heavy-ground-1
                   (start-animation 'heavy-charge-2 player))
                  (light-charge-2
                   (unless (interruptable-p (frame player))
                     (setf (clock player) 0.0)))
                  (heavy-charge-2
                   (unless (interruptable-p (frame player))
                     (setf (clock player) 0.0)))))))
       (handle-animation-states player ev))
      (:dashing
       (incf (dash-time player) dt)
       (setf (jump-time player) 100.0)
       (when (< (decf (vw (color player)) (* 4 dt)) 0)
         (setf (vw (color player)) 0.0))
       (or (and (< (dash-time player) (p! dash-evade-grace-time))
                (handle-evasion player)
                (setf (vw (color player)) 0.0))
           (cond ((or (< (p! dash-max-time) (dash-time player))
                      (and (< (p! dash-min-time) (dash-time player))
                           (not (retained 'dash))))
                  (setf (state player) :normal))
                 ((< (p! dash-dcc-end) (dash-time player)))
                 ((< (p! dash-dcc-start) (dash-time player))
                  (nv* vel (damp* (p! dash-dcc) (* 100 dt))))
                 ((< (p! dash-acc-start) (dash-time player))
                  (nv* vel (damp* (p! dash-acc) (* 100 dt))))
                 (T
                  (vsetf (color player) 1 1 1 1))))
       (when (typep (interactable player) 'rope)
         (nudge (interactable player) loc (* (direction player) 20)))
       ;; Adapt velocity if we are on sloped terrain
       ;; I'm not sure why this is necessary, but it is.
       (typecase ground
         (slope
          (when (v/= 0 vel)
            (let* ((normal (nvunit (vec2 (- (vy2 (slope-l ground)) (vy2 (slope-r ground)))
                                         (- (vx2 (slope-r ground)) (vx2 (slope-l ground))))))
                   (slope (vec (- (vy normal)) (vx normal)))
                   (proj (v* slope (v. slope vel)))
                   (angle (vangle slope (vunit vel))))
              (when (or (< angle (* PI 1/4)) (< (* PI 3/4) angle))
                (vsetf vel (vx proj) (vy proj))))))
         (null
          (nv* vel (damp* (p! dash-air-dcc) (* 100 dt)))))
       ;; Handle crawlspaces
       (when (/= 0 (vx vel))
         (let* ((off (tvec (+ (vx loc) (* (float-sign (vx vel)) (+ (vx size) 8)))
                           (+ (vy loc) (vy size) 8)))
                (ymin (- (vy loc) (vy size) 8))
                (pprev NIL)
                (prev NIL))
           (loop (let ((cur (scan +world+ off (lambda (hit) (not (collides-p player (hit-object hit) hit))))))
                   (when (and pprev (null prev) (or cur ground))
                     (setf (vw (color player)) 0.0)
                     (setf (vx vel) (* (float-sign (vx vel)) (vx (p! velocity-limit))))
                     (if cur
                         (setf (vy loc) (+ (vy (hit-location cur)) (vy size) 8))
                         (setf (vy loc) (- (vy pprev) (vy size) 8)))
                     (setf (air-time player) 0.0)
                     (setf (state player) :crawling)
                     (return))
                   (shiftf pprev prev (if cur (vcopy (hit-location cur)))))
                 (when (< (vy off) ymin)
                   (return))
                 (decf (vy off) 16)))))
      (:sliding
       (let ((dir (cond ((retained 'left)  -1)
                        ((retained 'right) +1)
                        (T                  0))))
         ;; Allow the player to influence movement.
         (if (= dir (float-sign (vx vel)))
             (when (<= (abs (vx vel)) (p! slide-acclimit))
               (incf (vx vel) (* dir (p! slide-acc))))
             (when (<= (p! slide-dcc) (abs (vx vel)))
               (incf (vx vel) (* dir (p! slide-dcc)))))
         ;; Slope sticky
         (when (typep ground 'slope)
           (let ((slope-steepness (*  (- (vy (slope-l ground)) (vy (slope-r ground))))))
             (cond ((= (direction player) (float-sign slope-steepness))
                    (incf (vy vel) -1)
                    (incf (vx vel) (* slope-steepness (p! slide-slope-acc))))
                   (T
                    (incf (vx vel) (* slope-steepness (p! slide-slope-dcc)))
                    (let* ((normal (nvunit (vec2 (- (vy2 (slope-l ground)) (vy2 (slope-r ground)))
                                                 (- (vx2 (slope-r ground)) (vx2 (slope-l ground))))))
                           (slope (vec (- (vy normal)) (vx normal)))
                           (proj (v* slope (v. slope vel))))
                      (vsetf vel (vx proj) (vy proj))))))))
       ;; Handle jumps
       (when (and (< (jump-time player) 0.0)
                  (< (air-time player) (p! coyote-time)))
         (trigger 'jump player)
         (setf (vy vel) (+ (p! jump-acc)
                           (if ground
                               (* 0.25 (max 0 (vy (velocity ground))))
                               0)))
         (setf ground NIL)
         (setf (jump-time player) 0.0))
       ;; Friction
       (if ground
           (setf (vx vel) (* (vx vel) (damp* (p! slide-friction) (* 100 dt))))
           (setf (vx vel) (* (vx vel) (damp* (p! air-dcc) (* 100 dt)))))
       (cond (ground
              (setf (air-time player) 0.0)
              (when (or (<= (abs (vx vel)) 1.0))
                (start-animation 'stumble player)))
             ((and (< 0.0 (vy vel))
                   (< 0.1 (jump-time player))
                   (< (air-time player) 0.02))
              (nv* vel (damp* 1.17 (* 100 dt)))))
       (when (and (retained 'jump)
                  (<= 0.05 (jump-time player) 0.15)
                  (< 0 (vy vel)))
         (setf (vy vel) (* (vy vel) (damp* (p! jump-mult) (* 100 dt)))))
       (nv+ vel (v* (gravity (medium player)) dt)))
      (:climbing
       (setf (visibility (stamina-wheel player)) 1.0)
       ;; Movement
       (let* ((top (if (= -1 (direction player))
                       (scan-collision +world+ (vec (- (vx loc) (vx size) 10) (- (vy loc) (vy size) 2)))
                       (scan-collision +world+ (vec (+ (vx loc) (vx size) 10) (- (vy loc) (vy size) 2)))))
              (attached (or (if (typep (svref collisions (if (< 0 (direction player)) 1 3)) '(or ground solid))
                                (svref collisions (if (< 0 (direction player)) 1 3)))
                            (interactable player)
                            top)))
         (setf (vx vel) 0f0)
         (when (or (not (retained 'climb))
                   (not (typep attached '(or (and ground (not slipblock)) (and solid (not half-solid)) rope)))
                   (<= (climb-strength player) 0))
           (setf (state player) :normal))
         (typecase attached
           (rope
            (setf (climb-strength player) (p! climb-strength))
            (vsetf (color player) 10 0 0 0)
            (nudge attached loc (* (direction player) -8))
            (cond ((retained 'left)
                   (let ((target-x (- (vx (location (interactable player))) (vx size))))
                     (unless (scan-collision +world+ (vec target-x (vy loc) (vx size) (vy size)))
                       (setf (direction player) +1)
                       (setf (vx loc) target-x))))
                  ((retained 'right)
                   (let ((target-x (+ (vx (location (interactable player))) (vx size))))
                     (unless (scan-collision +world+ (vec target-x (vy loc) (vx size) (vy size)))
                       (setf (direction player) -1)
                       (setf (vx loc) target-x))))))
           (moving-platform
            (trigger attached player)
            (nv+ (frame-velocity player) (velocity attached))))
         (if (retained 'down)
             (if (typep attached 'rope)
                 (harmony:play (// 'sound 'rope-slide-down)))
             (harmony:stop (// 'sound 'rope-slide-down)))
         (cond ((retained 'jump)
                (when (typep attached 'rope)
                  (nudge attached (location player) (* (direction player) 16)))
                (harmony:stop (// 'sound 'rope-slide-down))
                (setf (state player) :normal))
               ((and top (eq attached top))
                (setf (vy vel) (p! climb-up))
                (setf (vx vel) (* (direction player) (p! climb-up))))
               ((retained 'up)
                (unless (typep attached 'rope)
                  (decf (climb-strength player) dt))
                (if (< (vy vel) (p! climb-up))
                    (setf (vy vel) (p! climb-up))
                    (decf (vy vel) 0.1)))
               ((retained 'down)
                (setf (vy vel) (* (p! climb-down) -1)))
               (T
                (setf (vy vel) 0.0)))))
      (:crawling
       ;; Uncrawl on ground loss or manual
       (when (or (and (not ground)
                      (< 0.1 (air-time player)))
                 (and (not (retained 'crawl))
                      (and (not (svref collisions 0))
                           (null (scan-collision +world+ (vec (vx loc) (+ (vy loc) 18) (vx size) 1))))))
         (setf (state player) :normal)
         (setf (retained 'crawl) NIL)
         ;; Check ceiling and clip out.
         (when (scan-collision +world+ (vec (vx loc) (+ 2 (vy loc)) 8 16))
           (decf (vy loc) 16)))

       (setf (vx vel) (* 0.9 (vx vel)))
       (cond ((retained 'left)
              (setf (vx vel) (min (vx vel) (- (p! crawl)))))
             ((retained 'right)
              (setf (vx vel) (max (vx vel) (+ (p! crawl)))))
             (T
              (when (< (abs (vx vel)) 0.1)
                (setf (vx vel) 0.0))))
       ;; Slope sticky
       (when (and (<= (vy vel) 0) (typep ground 'slope))
         (if (= (signum (vx vel))
                (signum (- (vy (slope-l ground)) (vy (slope-r ground)))))
             (decf (vy vel) 1)))
       (nv+ vel (v* (gravity (medium player)) dt)))
      (:normal
       ;; Handle slide
       #-kandria-release
       (when (and (and (retained 'down))
                  (<= (p! walk-limit) (abs (vx vel))))
         (when (typep ground 'slope)
           (setf (direction player) (float-sign (- (vy (slope-l ground)) (vy (slope-r ground))))))
         (setf (state player) :sliding))
       
       ;; Handle jumps
       (when (< (jump-time player) 0.0)
         (cond ((or (typep (svref collisions 1) '(and (not null) (not platform)))
                    (typep (svref collisions 3) '(and (not null) (not platform)))
                    (and (typep (interactable player) 'rope)
                         (extended (interactable player))
                         (retained 'climb)))
                ;; Wall jump
                (let ((dir (if (svref collisions 1) -1.0 1.0))
                      (mov-dir (cond ((retained 'left) -1)
                                     ((retained 'right) +1)
                                     (T 0))))
                  (setf (jump-time player) 0.0)
                  (harmony:play (// 'sound 'player-jump))
                  (cond ((or (= dir mov-dir)
                             (not (retained 'climb)))
                         (setf (direction player) dir)
                         (setf (vy vel) (vy (p! walljump-acc)))
                         (setf (vx vel) (* dir (vx (p! walljump-acc)))))
                        ((<= -0.1 (climb-strength player))
                         (unless (typep (interactable player) 'rope)
                           (decf (climb-strength player) (p! climb-jump-cost)))
                         (setf (vy vel) (+ 0.3 (vy (p! walljump-acc))))))))
               ((< (air-time player) (p! coyote-time))
                ;; Ground jump
                (trigger 'jump player)
                (setf (vy vel) (+ (p! jump-acc)
                                  (if ground
                                      (* 0.25 (max 0 (vy (velocity ground))))
                                      0)))
                (setf ground NIL)
                (setf (jump-time player) 0.0))))
       
       ;; Test for climbing
       (when (and (retained 'climb)
                  (not (retained 'jump))
                  (< 0 (climb-strength player)))
         (cond ((typep (interactable player) 'rope)
                (let* ((direction (signum (- (vx (location (interactable player))) (vx loc))))
                       (target-x (+ (vx (location (interactable player))) (* direction -8))))
                  (when (scan-collision +world+ (vec target-x (vy loc) (vx size) (vy size)))
                    (setf direction (* -1 direction))
                    (setf target-x (+ (vx (location (interactable player))) (* direction -8))))
                  (unless (scan-collision +world+ (vec target-x (vy loc) (vx size) (vy size)))
                    (setf (direction player) direction)
                    (setf (vx loc) target-x)
                    (setf (state player) :climbing)
                    (return-from handle))))
               ((and (< -0.5 (vx vel)) (typep (svref collisions 1) '(or (and ground (not slipblock)) (and solid (not half-solid)))))
                (setf (direction player) +1)
                (setf (state player) :climbing)
                (return-from handle))
               ((and (< (vx vel) +0.5) (typep (svref collisions 3) '(or (and ground (not slipblock)) (and solid (not half-solid)))))
                (setf (direction player) -1)
                (setf (state player) :climbing)
                (return-from handle))))

       ;; Movement
       (cond (ground
              (setf (dash-exhausted player) NIL)
              (when (<= (climb-strength player) (p! climb-strength))
                (setf (climb-strength player) (min (p! climb-strength) (+ (climb-strength player) (* 10 (dt ev))))))
              (incf (vy vel) (min 0 (vy (velocity ground))))
              (cond ((retained 'left)
                     (setf (direction player) -1)
                     ;; Quick turns on the ground.
                     (when (< 0 (vx vel))
                       (setf (vx vel) 0))
                     (if (< (- ground-limit) (vx vel))
                         (decf (vx vel) ground-acc)
                         (setf (vx vel) (- ground-limit))))
                    ((retained 'right)
                     (setf (direction player) +1)
                     ;; Quick turns on the ground.
                     (when (< (vx vel) 0)
                       (setf (vx vel) 0))
                     (if (< (vx vel) ground-limit)
                         (incf (vx vel) ground-acc)
                         (setf (vx vel) ground-limit)))
                    (T
                     (setf (vx vel) 0))))
             ((retained 'left)
              (setf (direction player) -1)
              (when (< (- ground-limit) (vx vel))
                (decf (vx vel) (p! air-acc))))
             ((retained 'right)
              (setf (direction player) +1)
              (when (< (vx vel) ground-limit)
                (incf (vx vel) (p! air-acc)))))
       (when (typep (medium player) 'water)
         (cond ((retained 'down)
                (when (< (- ground-limit) (vy vel))
                  (decf (vy vel) (p! air-acc))))
               ((retained 'up)
                (when (< (vy vel) ground-limit)
                  (incf (vy vel) (p! air-acc))))))
       ;; Slope sticky
       (when (and (<= (vy vel) 0) (typep ground 'slope))
         (if (= (signum (vx vel))
                (signum (- (vy (slope-l ground)) (vy (slope-r ground)))))
             (decf (vy vel) 1)))
       ;; Air friction
       (unless ground
         (setf (vx vel) (* (vx vel) (damp* (p! air-dcc) (* 100 dt)))))
       ;; Jump progress
       (when (and (retained 'jump)
                  (<= 0.05 (jump-time player) 0.15)
                  (< 0 (vy vel)))
         (incf (vy vel) (* dt (p! jump-hold-acc))))
       (nv+ vel (v* (gravity (medium player)) dt))
       (when (and (null ground)
                  (null (retained 'down)))
         ;; FIXME: this should not affect wind speedup...
         (setf (vy vel) (max (- (p! slowfall-limit)) (vy vel))))
       ;; Limit when sliding down wall
       (cond ((and (null ground)
                   (or (typep (svref collisions 1) '(or ground moving-platform))
                       (typep (svref collisions 3) '(or ground moving-platform))))
              (when (and (< (vy vel) 0)
                         (< (slide-time player) (p! slide-ramp-time)))
                (setf (vy vel) (* (vy vel) (/ (slide-time player) (p! slide-ramp-time))))
                (incf (slide-time player) dt))
              (when (< (vy vel) (p! slide-limit))
                (setf (vy vel) (p! slide-limit)))
              (when (< (vy vel) -1)
                (nv+ (frame-velocity player) (velocity (or (svref collisions 1) (svref collisions 3))))))
             (T
              (setf (slide-time player) 0.0)))))
    (nvclamp (v- (p! velocity-limit)) vel (p! velocity-limit))
    (nv+ (frame-velocity player) vel)))

(defmethod handle :after ((ev tick) (player player))
  (setf (mixed:location harmony:*server*) (location player))
  (incf (jump-time player) (dt ev))
  (when (< 0 (limp-time player))
    (decf (limp-time player) (dt ev)))
  (let ((strength (climb-strength player)))
    (if (< strength (p! climb-strength))
        (if (and (< 0 strength 3) (eql :climbing (state player)))
            (harmony:play (// 'sound 'player-red-flashing) :location (location player))
            (harmony:stop (// 'sound 'player-red-flashing)))
        (harmony:stop (// 'sound 'player-red-flashing))))
  ;; Animations
  (let ((vel (velocity player))
        (collisions (collisions player)))
    (setf (playback-direction player) +1)
    (setf (playback-speed player) 1.0)
    (case (state player)
      (:climbing
       (setf (animation player) 'climb)
       (cond
         ((< (vy vel) 0)
          (setf (playback-direction player) -1)
          (setf (playback-speed player) 1.5))
         ((= 0 (vy vel))
          (setf (clock player) 0.0))))
      (:crawling
       (cond ((< 0 (vx vel))
              (setf (direction player) +1))
             ((< (vx vel) 0)
              (setf (direction player) -1)))
       (setf (animation player) 'crawl)
       (when (= 0 (vx vel))
         (setf (clock player) 0.0)))
      (:sliding
       (typecase (svref collisions 2)
         (slope
          (let ((slope-steepness (- (vy (slope-l (svref collisions 2))) (vy (slope-r (svref collisions 2))))))
            (if (= (float-sign slope-steepness) (direction player))
                (setf slope-steepness (abs slope-steepness))
                (setf slope-steepness (- (abs slope-steepness))))
            (cond ((< +12 slope-steepness) (setf (animation player) 'slide-1x1))
                  ((<  +7 slope-steepness) (setf (animation player) 'slide-1x2))
                  ((<  +1 slope-steepness) (setf (animation player) 'slide-1x3))
                  ((> -12 slope-steepness) (setf (animation player) 'slide-1x1up))
                  ((>  -7 slope-steepness) (setf (animation player) 'slide-1x2up))
                  ((>  -1 slope-steepness) (setf (animation player) 'slide-1x3up)))))
         (null
          (if (< 0 (vy vel))
              (setf (animation player) 'jump)
              (setf (animation player) 'fall)))
         (T
          (setf (animation player) 'slide-flat))))
      (:normal
       (cond ((and (< 0 (vy vel)) (not (typep (svref collisions 2) 'moving-platform)))
              (setf (animation player) 'jump))
             ((null (svref collisions 2))
              (setf (look-time player) 0.0)
              (cond ((< (air-time player) 0.1))
                    ((typep (svref collisions 1) '(or ground moving-platform))
                     (setf (animation player) 'slide)
                     (setf (direction player) +1)
                     (when (< (clock player) 0.01)
                       (trigger 'slide player :direction -1)))
                    ((typep (svref collisions 3) '(or ground moving-platform))
                     (setf (animation player) 'slide)
                     (setf (direction player) -1)
                     (when (< (clock player) 0.01)
                       (trigger 'slide player :direction +1)))
                    (T
                     (setf (animation player) 'fall))))
             ((< 0 (abs (vx vel)))
              (setf (look-time player) 0.0)
              (cond ((and (not (eql :keyboard +input-source+))
                          (< (abs (gamepad:axis :l-h +input-source+)) 0.75)
                          (< (abs (gamepad:axis :dpad-h +input-source+)) 0.75))
                     (setf (playback-speed player) (/ (abs (vx vel)) (p! slowwalk-limit)))
                     (if (< 0 (limp-time player))
                         (setf (animation player) 'limp-walk)
                         (setf (animation player) 'walk)))
                    (T
                     (setf (playback-speed player) (/ (abs (vx vel)) (p! walk-limit)))
                     (if (< 0 (limp-time player))
                         (setf (animation player) 'limp-run)
                         (setf (animation player) 'run)))))
             ((retained 'up)
              (cond ((< (look-time player) (p! look-delay))
                     (incf (look-time player) (dt ev))
                     (setf (animation player) 'look-up))
                    (T
                     (duck-camera 0 (+ (p! look-offset))))))
             ((retained 'down)
              (cond ((< (look-time player) (p! look-delay))
                     (incf (look-time player) (dt ev))
                     (setf (animation player) 'look-down))
                    (T
                     (duck-camera 0 (- (p! look-offset))))))
             (T
              (setf (look-time player) 0.0)
              (if (< 0 (limp-time player))
                  (setf (animation player) 'limp-stand)
                  (setf (animation player) 'stand))))))
    (cond ((eql (name (animation player)) 'slide)
           (harmony:play (// 'sound 'player-wall-slide)))
          (T
           (harmony:stop (// 'sound 'player-wall-slide))))))

(defmethod handle ((ev switch-region) (player player))
  (let* ((region (slot-value ev 'region))
         (other (find-chunk player)))
    (unless other
      (warn "Player is somehow outside all chunks, picking first chunk we can get.")
      (setf other (for:for ((entity over region))
                    (when (typep entity 'chunk) (return entity))))
      (unless other
        (error "What the fuck? Could not find any chunks.")))
    (snap-to-target (unit :camera T) player)
    (switch-chunk other)))

(defmethod handle ((ev switch-chunk) (player player))
  (unless (eq (chunk ev) (chunk player))
    (let ((loc (vcopy (location player))))
      (when (v/= 0 (velocity player))
        (nv+ loc (v* (vunit (velocity player)) +tile-size+)))
      (setf (unlocked-p (chunk ev)) T)
      (setf (chunk player) (chunk ev))
      (setf (spawn-location player) loc))))

(defmethod oob ((player player) (new chunk))
  (switch-chunk new))

(defmethod oob ((player player) (none null))
  (unless (or (find-panel 'editor)
              (eql :noclip (state player)))
    (setf (state player) :oob)
    (transition (respawn player))))

(defmethod respawn ((player player))
  (interrupt-movement-trace player)
  ;; Actually respawn now.
  (switch-chunk (chunk player))
  (setf (animation player) 'stand)
  (vsetf (velocity player) 0 0)
  (vsetf (frame-velocity player) 0 0)
  (place-on-ground player (spawn-location player))
  (setf (state player) :normal)
  (snap-to-target (unit :camera T) player))

(defmethod damage-output ((player player))
  (ceiling
   (* (damage (frame player))
      (setting :gameplay :damage-output))))

(defmethod hurt ((player player) (damage integer))
  (call-next-method player (floor (* damage
                                     (setting :gameplay :damage-input)))))

(defmethod hurt :after ((player player) (by integer))
  (setf (clock (progression 'hurt +world+)) 0)
  (start (progression 'hurt +world+))
  (setf (combat-time player) 0f0)
  (shake-camera :intensity 5))

(defmethod (setf limp-time) :after (time (player player))
  (when (< 0 time)
    (setf (combat-time player) 0.0))
  (setf (strength (unit 'distortion +world+)) (* (clamp 0.0 (/ time 5) 1.0) 0.6)))

(defmethod (setf health) :before (health (player player))
  (when (< (health player) health)
    (setf (combat-time player) 0f0))
  (cond ((<= 0 (/ health (maximum-health player)) 0.15)
         (setf (limp-time player) 10.0)
         (harmony:play (// 'sound 'player-low-health))
         (setf (clock (progression 'low-health +world+)) 0)
         (start (progression 'low-health +world+)))
        (T
         (harmony:stop (// 'sound 'player-low-health))
         (setf (limp-time player) 0.0))))

(defmethod kill ((player player))
  (cond ((<= (health player) 0)
         (setf (state player) :dying)
         (setf (animation player) 'die)
         (setf (override (unit 'environment +world+)) 'null)
         (harmony:play (// 'sound 'player-die))
         (setf (clock (progression 'death +world+)) 0f0)
         (start (progression 'death +world+)))
        (T
         (rumble :intensity 10.0)
         (vsetf (velocity player) 0 0)
         (setf (animation player) 'die)
         (setf (state player) :respawning)
         (harmony:play (// 'sound 'player-die-platforming))
         (transition
           (respawn player)))))

(defmethod die ((player player)))

(defun player-screen-y ()
  (* (- (vy (location (unit 'player T))) (vy (location (unit :camera T))))
     (view-scale (unit :camera T))))

(defmethod apply-transforms progn ((player player))
  (declare (optimize speed))
  (let ((x (1+ (clamp -0.5
                      (1+ (/ (- (vy (velocity player)) (p! slowfall-limit))
                             (- (vy (p! velocity-limit)) (p! slowfall-limit))))
                       0))))
    (scale-by x 1 1)))

(defmethod render :before ((player player) (program shader-program))
  (setf (uniform program "color_mask") (color player)))

(define-class-shader (player :fragment-shader -2)
  "uniform vec4 color_mask = vec4(1,1,1,0);
out vec4 color;

void main(){
  color.rgb = mix(color.rgb,color_mask.rgb,color_mask.a);
}")

(define-setting-observer god-mode :gameplay :god-mode (value)
  (when (unit 'player T)
    (setf (invincible-p (unit 'player T)) value)))

(define-setting-observer palette :gameplay :palette (value)
  (when (unit 'player T)
    (setf (palette-index (unit 'player T))
          (or (position value (palettes (asset 'kandria 'player)) :test #'equal) 0))))
