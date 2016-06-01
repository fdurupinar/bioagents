(defpackage :trips-asd
  (:use :asdf
        :common-lisp))
(in-package :trips-asd)

;;; For now, the biggest reason for having this ASD is so that other
;;; components can find us using a call like:
;;; (asdf:system-relative-pathname :trips)
;;;
(defsystem :trips
  :perform (load-op :before (o c)
                    ;; First load the config so that TRIPS_BASE is set properly.
                    (load (system-relative-pathname :trips
                                                    "cabot/src/config/lisp/trips.lisp"))
                    ;; Then load the core system.
                    (load (system-relative-pathname :trips
                                                    "cabot/src/Systems/core/system.lisp"))))


(defsystem :trips/util
  :depends-on (:trips)
  :perform (load-op :before (o c)
                    (load (system-relative-pathname :trips
                                                    "cabot/src/util/defsys.lisp"))))

(defsystem :trips/ont
  :depends-on (:trips)
  :perform (load-op :before (o c)
                    (load (system-relative-pathname :trips
                                                    "cabot/src/OntologyManager/ont-pkg.lisp"))))


