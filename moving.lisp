(in-package #:org.shirakumo.fraf.kandria)

(define-global +default-medium+ (make-instance 'air))

(defclass moving (game-entity)
  ((collisions :initform (make-array 4 :initial-element NIL) :reader collisions)
   (medium :initform +default-medium+ :accessor medium)
   (air-time :initform 1.0 :accessor air-time)))

(defmethod tentative-scan (entity bounds tentative offset)
  offset)

(defmethod tentative-scan ((entity solid) bounds tentative offset)
  (let ((hit (aref tentative offset)))
    (setf (hit-object hit) entity)
    (v<- (hit-location hit) (location entity))
    (1+ offset)))

(defmethod tentative-scan ((chunk chunk) bounds tentative offset)
  (declare (type vec4 bounds))
  (declare (type simple-vector tentative +surface-blocks+))
  (declare (type (unsigned-byte 8) offset))
  (declare (optimize speed))
  (let* ((siz (the vec2 (bsize chunk)))
         (loc (the vec2 (location chunk)))
         (tilemap (pixel-data chunk))
         (w (truncate (the (single-float 0.0 10000000.0) (vx2 (size chunk)))))
         (h (truncate (the (single-float 0.0 10000000.0) (vy2 (size chunk)))))
         (t-s (load-time-value (float +tile-size+ 0f0)))
         (x- (floor (+ (- (vx4 bounds) (vx2 loc)) (vx2 siz)) t-s))
         (x+ (floor (+ (- (vz4 bounds) (vx2 loc)) (vx2 siz)) t-s))
         (y- (floor (+ (- (vy4 bounds) (vy2 loc)) (vy2 siz)) t-s))
         (y+ (floor (+ (- (vw4 bounds) (vy2 loc)) (vy2 siz)) t-s))
         (max (length tentative)))
    (declare (type (simple-array (unsigned-byte 8) (*)) tilemap))
    (declare (type (signed-byte 32) x- x+ y- y+))
    (cl:block loops
      (loop for y from (max y- 0) to (min y+ (1- h))
            do (loop for x from (max x- 0) to (min x+ (1- w))
                     for i = (* (+ x (* y w)) 2)
                     for tile = (aref tilemap (+ i 0))
                     do (when (and (= 0 (aref tilemap (+ i 1)))
                                   (< 0 tile))
                          (let ((hit (aref tentative offset)))
                            (setf (hit-object hit) (aref +surface-blocks+ tile))
                            (vsetf (hit-location hit)
                                   (+ (* x t-s) (/ t-s 2) (- (vx loc) (vx siz)))
                                   (+ (* y t-s) (/ t-s 2) (- (vy loc) (vy siz))))
                            (when (= max (incf offset))
                              (return-from loops)))))))
    offset))

(defun perform-collision-tick (moving dt)
  (declare (type single-float dt))
  (declare (optimize speed))
  (let* ((tentative (load-time-value (map-into (make-array 16) #'%make-hit)))
         (found 0)
         (vel (nv* (frame-velocity moving) (* 100.0 dt)))
         (len (vlength vel))
         (loc (location moving))
         (siz (bsize moving))
         (v/2 (v* vel 0.5))
         (bounds (vec (- (+ (vx v/2) (vx loc)) (abs (vx v/2)) (vx siz))
                      (- (+ (vy v/2) (vy loc)) (abs (vy v/2)) (vy siz))
                      (+ (+ (vx v/2) (vx loc)) (abs (vx v/2)) (vx siz))
                      (+ (+ (vy v/2) (vy loc)) (abs (vy v/2)) (vy siz)))))
    (declare (type (unsigned-byte 8) found))
    ;; Scan for applicable entities
    (bvh:do-fitting (entity (bvh (region +world+)) bounds)
      (when (not (eq entity moving))
        (setf found (tentative-scan entity bounds tentative found))
        (when (= 16 found)
          (return))))
    ;; Stub out other tentative values
    (loop for i from found below (length tentative)
          do (vsetf (hit-location (aref tentative i))
                    MOST-POSITIVE-SINGLE-FLOAT MOST-POSITIVE-SINGLE-FLOAT))
    ;; Sort so we process close hits first
    (flet ((dist (hit)
             (declare (type hit hit))
             (let ((l (hit-location hit)))
               (if (= (vx l) MOST-POSITIVE-SINGLE-FLOAT)
                   MOST-POSITIVE-SINGLE-FLOAT
                   (vsqrdistance l loc)))))
      (sort tentative #'< :key #'dist))
    (flet ((try-collide ()
             (loop for i from 0 below found
                   for hit = (aref tentative i)
                   do (when (collides-p moving (hit-object hit) hit)
                        (collide moving (hit-object hit) hit)))))
      ;; Step over the velocity until we only have remainders
      (when (<= 1 len)
        (loop with vstep = (v/ vel len)
              while (<= 1 len)
              do (nv+ loc vstep)
                 (nv- vel vstep)
                 (decf len 1.0)
                 (try-collide)
                 (when (= 0 (vx vel)) (setf (vx vstep) 0))
                 (when (= 0 (vy vel)) (setf (vy vstep) 0))))
      ;; Process remainder
      (nv+ loc vel)
      (vsetf vel 0 0)
      (try-collide))))

(defmethod handle ((ev tick) (moving moving))
  (when (next-method-p) (call-next-method))
  (let ((loc (location moving))
        (*current-event* ev)
        (size (bsize moving))
        (collisions (collisions moving)))
    ;; Scan for medium
    (let ((medium (bvh:do-fitting (entity (bvh (region +world+)) moving +default-medium+)
                    (when (typep entity 'medium)
                      (return entity)))))
      (setf (medium moving) medium)
      (nv* (velocity moving) (drag medium))
      (if (and (typep medium 'sized-entity)
               (within-p medium moving))
          (submerged moving medium)
          (submerged moving +default-medium+)))
    ;; Scan for hits
    (fill collisions NIL)
    (perform-collision-tick moving (dt ev))
    (when (eq (svref collisions 2) (svref collisions 1))
      (setf (svref collisions 1) NIL))
    (when (eq (svref collisions 2) (svref collisions 3))
      (setf (svref collisions 3) NIL))
    ;; Point test for adjacent walls
    (flet ((test (hit)
             (not (is-collider-for moving (hit-object hit)))))
      (let ((l (scan +world+ (vec (- (vx loc) (vx size) 1) (vy loc) 1 (1- (vy size))) #'test)))
        (when l
          (setf (aref collisions 3) (hit-object l))))
      (let ((r (scan +world+ (vec (+ (vx loc) (vx size) 1) (vy loc) 1 (1- (vy size))) #'test)))
        (when r
          (setf (aref collisions 1) (hit-object r))))
      (let ((u (scan +world+ (vec (vx loc) (+ (vy loc) (vy size) 1.5) (1- (vx size)) 1) #'test)))
        (when u
          (setf (aref collisions 0) (hit-object u))))
      (let ((b (scan +world+ (vec (vx loc) (- (vy loc) (vy size) 1.5) (1- (vx size)) 1) #'test)))
        (when b
          (setf (aref collisions 2) (hit-object b))))))
  (incf (air-time moving) (dt ev)))

(defmethod collides-p ((moving moving) (solid half-solid) hit)
  (= 0 (vy (hit-normal hit))))

(defmethod collide :after ((moving moving) (block block) hit)
  (when (< 0 (vy (hit-normal hit)))
    (setf (air-time moving) 0.0)))

(defmethod collide :after ((moving moving) (solid solid) hit)
  (when (< 0 (vy (hit-normal hit)))
    (setf (air-time moving) 0.0)))

(defmethod collide ((moving moving) (block block) hit)
  ;; clamp velocity and push out
  (cond ((/= 0 (vx (hit-normal hit)))
         (setf (vx (frame-velocity moving)) 0)
         (cond ((< 0 (vx (hit-normal hit)))
                (setf (svref (collisions moving) 3) block)
                (setf (vx (location moving)) (+ (vx (hit-location hit)) (vx (bsize block)) (vx (bsize moving)))))
               (T
                (setf (svref (collisions moving) 1) block)
                (setf (vx (location moving)) (- (vx (hit-location hit)) (vx (bsize block)) (vx (bsize moving)))))))
        (T
         (setf (vy (frame-velocity moving)) 0)
         (cond ((< 0 (vy (hit-normal hit)))
                (setf (vy (velocity moving)) (max 0 (vy (velocity moving))))
                (setf (svref (collisions moving) 2) block)
                (setf (vy (location moving)) (+ (vy (hit-location hit)) (vy (bsize block)) (vy (bsize moving)))))
               (T
                (setf (svref (collisions moving) 0) block)
                (setf (vy (location moving)) (- (vy (hit-location hit)) (vy (bsize block)) (vy (bsize moving)))))))))

(defmethod collides-p ((moving moving) (block platform) hit)
  (and (< 0 (vy (hit-normal hit)))
       (<= (+ (vy (hit-location hit)) (floor +tile-size+ 2) -2)
           (- (vy (location moving)) (vy (bsize moving))))))

(defmethod collide ((moving moving) (block death) hit)
  (kill moving)
  (call-next-method))

(defmethod collides-p ((moving moving) (block spike) hit)
  (let ((vel (if (v= (frame-velocity moving) 0.0) (velocity moving) (frame-velocity moving))))
    (unless (v= vel 0.0)
      (let ((angle (vangle (spike-normal block) vel))
            (loc (nv+ (v* vel 0.5) (location moving))))
        (and (<= 85 (rad->deg angle) 185)
             (if (/= 0 (vx (spike-normal block)))
                 (<= (abs (- (vx (hit-location hit)) (vx loc))) 7)
                 (<= (abs (- (vy (hit-location hit)) (vy loc))) 7)))))))

(defmethod collide ((moving moving) (block spike) hit)
  (kill moving))

(defmethod collide ((moving moving) (block slope) hit)
  (let* ((loc (location moving))
         (siz (bsize moving))
         (bloc (hit-location hit))
         (bsiz (bsize block))
         (l (vy (slope-l block)))
         (r (vy (slope-r block)))
         (dx (- (vx loc) (- (vx siz)) (vx bloc)))
         (tt (clamp 0.0 (/ (+ dx (float-sign (- r l) (vx bsiz))) 2 (vx bsiz)) 1.0))
         (y (+ (vy bloc) (vy siz) l (* tt (- r l)))))
    (when (<= (vy loc) y)
      (setf (vy loc) y)
      (setf (svref (collisions moving) 2) block)
      (setf (vy (velocity moving)) (max 0 (vy (velocity moving)))))))

(defmethod collide ((moving moving) (other sized-entity) hit)
  ;; clamp velocity and push out
  (cond ((/= 0 (vx (hit-normal hit)))
         (setf (vx (frame-velocity moving)) 0)
         (cond ((< 0 (vx (hit-normal hit)))
                (setf (svref (collisions moving) 3) other)
                (setf (vx (location moving)) (+ (vx (hit-location hit)) (vx (bsize other)) (vx (bsize moving)))))
               (T
                (setf (svref (collisions moving) 1) other)
                (setf (vx (location moving)) (- (vx (hit-location hit)) (vx (bsize other)) (vx (bsize moving)))))))
        (T
         (setf (vy (frame-velocity moving)) 0)
         (cond ((< 0 (vy (hit-normal hit)))
                (setf (vy (velocity moving)) (max 0 (vy (velocity moving))))
                (setf (svref (collisions moving) 2) other)
                (setf (vy (location moving)) (+ (vy (hit-location hit)) (vy (bsize other)) (vy (bsize moving)))))
               (T
                (setf (svref (collisions moving) 0) other)
                (setf (vy (location moving)) (- (vy (hit-location hit)) (vy (bsize other)) (vy (bsize moving)))))))))

(defmethod collide :after ((moving moving) (entity game-entity) hit)
  (when (and (< 0 (vy (hit-normal hit)))
             (<= (vy (velocity entity)) 0))
    (nv+ (frame-velocity moving) (velocity entity))))

(defmethod is-collider-for ((moving moving) (stopper stopper)) NIL)
(defmethod interactable-p ((elevator elevator)) T)

(defun place-on-ground (entity loc &optional (xdiff 0) (ydiff 0))
  (let* ((chunk (find-chunk loc))
         (ground (when chunk (find-ground chunk loc))))
    (if ground
        (vsetf (location entity)
               (random* (vx ground) xdiff)
               (+ (vy ground) (vy (bsize entity))))
        (vsetf (location entity)
               (random* (vx loc) xdiff)
               (+ (- (vy loc) ydiff) (vy (bsize entity)) 1)))))


(defmethod collides-p :around ((entity game-entity) other hit)
  (let* ((loc (location entity))
         (siz (bsize entity))
         (bloc (hit-location hit))
         (bsiz (bsize other)))
    (when (and (< (- (vx loc) (vx siz) (vx bsiz)) (vx bloc) (+ (vx loc) (vx siz) (vx bsiz)))
               (< (- (vy loc) (vy siz) (vy bsiz)) (vy bloc) (+ (vy loc) (vy siz) (vy bsiz))))
      ;; We are intersecting, compute normal
      (let ((dx (- (vx loc) (vx bloc)))
            (dy (- (vy loc) (vy bloc))))
        (if (< (/ (abs dy) (+ (vy siz) (vy bsiz)))
               (/ (abs dx) (+ (vx siz) (vx bsiz))))
            (if (< 0 dx)
                (vsetf (hit-normal hit) +1 0)
                (vsetf (hit-normal hit) -1 0))
            (if (< 0 dy)
                (vsetf (hit-normal hit) 0 +1)
                (vsetf (hit-normal hit) 0 -1))))
      (call-next-method))))

(defmethod collide ((entity game-entity) (block block) hit)
  ;; clamp velocity and push out
  (cond ((/= 0 (vx (hit-normal hit)))
         (setf (vx (frame-velocity entity)) 0)
         (cond ((< 0 (vx (hit-normal hit)))
                (setf (vx (location entity)) (+ (vx (hit-location hit)) (vx (bsize block)) (vx (bsize entity)))))
               (T
                (setf (vx (location entity)) (- (vx (hit-location hit)) (vx (bsize block)) (vx (bsize entity)))))))
        (T
         (setf (vy (frame-velocity entity)) 0)
         (cond ((< 0 (vy (hit-normal hit)))
                (setf (vy (velocity entity)) (max 0 (vy (velocity entity))))
                (setf (vy (location entity)) (+ (vy (hit-location hit)) (vy (bsize block)) (vy (bsize entity)))))
               (T
                (setf (vy (location entity)) (- (vy (hit-location hit)) (vy (bsize block)) (vy (bsize entity)))))))))

(defmethod collide ((entity game-entity) (block slope) hit)
  (let* ((loc (location entity))
         (siz (bsize entity))
         (bloc (hit-location hit))
         (bsiz (bsize block))
         (l (vy (slope-l block)))
         (r (vy (slope-r block)))
         (dx (- (vx loc) (- (vx siz)) (vx bloc)))
         (tt (clamp 0.0 (/ (+ dx (float-sign (- r l) (vx bsiz))) 2 (vx bsiz)) 1.0))
         (y (+ (vy bloc) (vy siz) l (* tt (- r l)))))
    (when (<= (vy loc) y)
      (setf (vy loc) y)
      (setf (vy (velocity entity)) (max 0 (vy (velocity entity)))))))

(defmethod collide ((entity game-entity) (other sized-entity) hit)
  ;; clamp velocity and push out
  (cond ((/= 0 (vx (hit-normal hit)))
         (setf (vx (frame-velocity entity)) 0)
         (cond ((< 0 (vx (hit-normal hit)))
                (setf (vx (location entity)) (+ (vx (hit-location hit)) (vx (bsize other)) (vx (bsize entity)))))
               (T
                (setf (vx (location entity)) (- (vx (hit-location hit)) (vx (bsize other)) (vx (bsize entity)))))))
        (T
         (setf (vy (frame-velocity entity)) 0)
         (cond ((< 0 (vy (hit-normal hit)))
                (setf (vy (location entity)) (+ (vy (hit-location hit)) (vy (bsize other)) (vy (bsize entity)))))
               (T
                (setf (vy (location entity)) (- (vy (hit-location hit)) (vy (bsize other)) (vy (bsize entity)))))))))
