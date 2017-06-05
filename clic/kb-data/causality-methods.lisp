;;; ------------------------------------------------------------
;;; Bio methods defining the goal hierarchy and exec behavior for
;;; phosphoproteomics causality agent (PCA)

(:in-context exec-methods)


;; ------------------------------
;; FIND-CAUSAL-PATH
;; ------------------------------

(kbop:method
 :matches ((evaluate ?goal))
 :pre ((some (is-ask-what ONT::STATUS ?goal ?what)
             (is-ask-what ONT::METHOD ?goal ?what))
       (suchthat ?what ?st)
       (instance-of ?st ?type)
       (:set-member ?type (set-fn ONT::ACTIVATE ONT::MODULATE))

       (affected ?st ?affected)
       (some (dbname ?affected ?targetId))
       (get-term-xml ?affected ?affected-xml)

       (agent ?st ?agent)
       (some (dbname ?agent ?sourceId))
       (get-term-xml ?agent ?source-xml))
 :on-ready ((:note "ACCEPTABLE" ?what)
            (:store (evaluate-result ?goal acceptable)))
 :result success)


(kbop:method
 :matches ((what-next ?goal ?reply-id))
 :pre ((some (is-ask-what ONT::STATUS ?goal ?what)
             (is-ask-what ONT::METHOD ?goal ?what))
       (suchthat ?what ?st)
       (instance-of ?st ?type)
       (:set-member ?type (set-fn ONT::ACTIVATE ONT::MODULATE))

       (affected ?st ?affected)
       (some (dbname ?affected ?targetId))
       (get-term-xml ?affected ?affected-xml)

       (agent ?st ?agent)
       (some (dbname ?agent ?sourceId))
       (get-term-xml ?agent ?source-xml))
 :on-ready ((:gentemp ?query-id "qca-")
            (:store (query ?query-id (find-causal-path
                                      :targetId ?affected-xml
                                      :sourceId ?source-xml)))
            (:dbug "Ask QCA if FIND-CAUSAL-PATH"
                   "for affected" ?affected ?target)
            (:subgoal (ask-bioagents ?query-id ?goal))
            (:subgoal (retrieve-nl-explanation ?query-id ?goal ?reply-id))))

(kbop:method
 :matches ((retrieve-nl-explanation ?query-id ?goal ?reply-id))
 :pre ((answer ?query-id ?ans)
       (paths ?ans ?paths))
 :on-ready (;; Get the NLG explanation.
            (:gentemp ?nlg-id "causality-nlg-")
            (:subgoal (get-causality-nlg-text ?goal ?paths ?nlg-id))
            ;; Store a useful version of it.
            (:subgoal (store-nlg-utterance ?nlg-id ?ans))
            (:subgoal (report-answer ?query-id ?goal ?reply-id))))

(kbop:method
 :matches ((retrieve-nl-explanation ?query-id ?goal ?reply-id))
 :pre ((answer ?query-id (list-fn failure no_path_found)))
 :on-ready (;; No path was found.
            (:dbug "CausalityAgent could not find a causal relationship.")
            (:subgoal (report-answer ?query-id ?goal ?reply-id))))

;;(kbop:method
;; :matches ((retrieve-nl-explanation ?query-id ?goal ?reply-id))
;; :pre ((answer ?query-id (list-fn failure)))
;; :on-ready (;; No causal relationship was found.
;;            (:dbug "CausalityAgent could not find a causal relationship.")
;;            (:subgoal (report-answer ?query-id ?goal ?reply-id))))

(kbop:method
 :matches ((store-nlg-utterance ?nlg-id ?target))
 :pre ((answer ?nlg-id ?ans)
       (nl ?ans ?nls))
 :on-ready (;; Here we are storing the list of NL utterances. We
            ;; *could* assemble them into a single string, like the
            ;; bio-model-building methods do. But it's probably better
            ;; not to, since the generate code should really be the
            ;; one doing smart things.
            (:store (nl ?target ?nls)))
 :result success)


 ;;FUNDA
 ;;; ------------------------------------------------------------
 ;;; Get natural language explanations for things.

 (kbop:method
  :matches ((get-causality-nlg-text ?main-goal ?statement-list ?nlg-id))
  :priority 1
  :pre ((:uninferrable (some (:symbolp ?statement-list)
                             (:stringp ?statement-list)))
        (:cardinality ?statement-list ?size)
        (:< 0 ?size)
        ;; FIXME But what should happen if there are more than one?
        (:elt-at ?statement-list 0 ?statements))
  :on-ready ((:store (query ?nlg-id
                            (INDRA-TO-NL :statements ?statements)))
             (:subgoal (ask-bioagents ?nlg-id ?main-goal))))

 (kbop:method
  :matches ((get-causality-nlg-text ?main-goal ?statements ?nlg-id))
  :priority -1
  :on-ready ((:store (query ?nlg-id
                            (INDRA-TO-NL :statements ?statements)))
             (:subgoal (ask-bioagents ?nlg-id ?main-goal))))


;;
;;-----------------------------------------------------------------
;;
;;; ------------------------------------------------------------
;;; Bio methods defining the goal hierarchy and exec behavior for
;;; causality and correlation queries
;;;
(:in-context exec-methods)

;; ------------------------------
;; IS-CAUSALITY-TARGET
;; ------------------------------

(kbop:method
 :matches ((evaluate ?goal))
 :pre ((is-ask-what ONT::PHOSPHORYLATION ?goal ?what)
       (agent ?what ?agent)
       (:uninferrable (instance-of ?agent ONT::GENE-PROTEIN))
       )
 :on-ready ((:note "ACCEPTABLE")
            (:store (evaluate-result ?goal acceptable)))
 :result success)

(kbop:method
 :matches ((what-next ?goal ?reply-id))
 :pre ((is-ask-what ONT::PHOSPHORYLATION ?goal ?what)
       (agent ?what ?agent)
       (:uninferrable (instance-of ?agent ONT::GENE-PROTEIN))
       (get-term-xml ?agent ?agent-xml)
       (affected ?what ?affected)
       (get-term-xml ?affected ?affected-xml))
 :on-ready ((:gentemp ?query-id "causality-query-")
            (:store (query ?query-id (is-causality-target
                                      :causality ?agent-xml
                                      :target ?affected-xml)))
            (:dbug "Ask CAUSALITY if IS-CAUSALITY-TARGET for agent" ?agent
                   "and affected" ?affected)
            (:subgoal (ask-bioagents ?query-id ?goal))
            (:subgoal (retrieve-nl-explanation ?query-id ?goal ?reply-id))))
            ;;(:subgoal (report-answer ?query-id ?what ?goal ?reply-id))))

;; ------------------------------
;; FIND-CAUSALITY-SOURCE
;; ------------------------------

(kbop:method
 :matches ((evaluate ?goal))
 :pre ((is-ask-what ONT::PROTEIN ?goal ?what)
       (phosphorylated-by-what ?what ?affected))
 :on-ready ((:note "ACCEPTABLE")
            (:store (evaluate-result ?goal acceptable)))
 :result success)



(:store (query ?query-id (dataset-correlated-entity
                                                  :source ?affected-xml)))


(kbop:method
 :matches ((ask-correlation ?affected-xml ?goal ?reply-id))

 :on-ready ((:gentemp ?query-id "correlation-query-")
            (:store (query ?query-id (dataset-correlated-entity
                                                              :source ?affected-xml)))
            (:subgoal (ask-bioagents ?query-id ?goal))))


(kbop:method
 :matches ((what-next ?goal ?reply-id))
 :pre ((is-ask-what ONT::GENE ?goal ?what)
       (phosphorylated-by-what ?what ?affected)
       (get-query-type ?what ?affected ?query-type)
       (get-term-xml ?affected ?affected-xml)
       )
 :on-ready ((:gentemp ?query-id "causality-query-")
            (:store (query ?query-id (find-causality-source
                                      :source ?affected-xml :type ?query-type)))
            (:store (source ?query-id ?affected))
            (:dbug "Ask CAUSALITY to FIND-CAUSALITY-SOURCE"
                   "for affected" ?affected)
            (:subgoal (ask-bioagents ?query-id ?goal))
            (:subgoal (retrieve-nl-explanation ?query-id ?goal ?reply-id))
            ;;Create a new query
            (:subgoal (ask-correlation ?affected-xml ?goal ?reply-id))))





;; ------------------------------
;; FIND-CAUSALITY-TARGET
;; ------------------------------

(kbop:method
 :matches ((evaluate ?goal))
 :pre ((is-ask-what ONT::GENE ?goal ?what))
 :on-ready ((:note "ACCEPTABLE")
            (:store (evaluate-result ?goal acceptable)))
 :result success)

(kbop:method
 :matches ((what-next ?goal ?reply-id))
 :pre ((is-ask-what ONT::GENE ?goal ?what)
       (agent ?query ?agent)
       (get-term-xml ?agent ?agent-xml)
       (some (instance-of ?query ONT::PHOSPHORYLATION)
       (instance-of ?query ONT::DEPHOSPHORYLATION)
       (instance-of ?query ONT::INCREASE)
       (instance-of ?query ONT::DECREASE)
       (instance-of ?query ONT::ACTIVATE)
       (instance-of ?query ONT::INHIBIT)
       (instance-of ?query ONT::MODULATE)
       )
       (affected ?query ?what)
       (get-query-type ?agent ?what ?query-type)
       )
 :on-ready ((:gentemp ?query-id "causality-query-")
            (:store (query ?query-id (find-causality-target
                                      :target ?agent-xml :type ?query-type)))
            (:store (target ?query-id ?agent))
            (:dbug "Ask CAUSALITY to FIND-CAUSALITY-TARGET"
                   "for agent" ?agent)
            (:subgoal (ask-bioagents ?query-id ?goal))
            (:subgoal (retrieve-nl-explanation ?query-id ?goal ?reply-id))))



;;; ------------------------------------------------------------
;;; Some rules

(:in-context collab-context)

(<< (phosphorylated-by-what ?what ?affected)
    (agent ?query ?what)
    (some (instance-of ?query ONT::PHOSPHORYLATION)
    (instance-of ?query ONT::DEPHOSPHORYLATION)
    (instance-of ?query ONT::INCREASE)
    (instance-of ?query ONT::DECREASE)
    (instance-of ?query ONT::ACTIVATE)
    (instance-of ?query ONT::INHIBIT)
    (instance-of ?query ONT::MODULATE))
    (affected ?query ?affected))


(<< (get-query-type ?what ?affected ?query-type)
    (agent ?query ?what)
    (instance-of ?query ONT::INCREASE)
    (affected ?query ?affected)
    (:assign ?query-type "increase"))

(<< (get-query-type ?what ?affected ?query-type)
    (agent ?query ?what)
    (instance-of ?query ONT::DECREASE)
    (affected ?query ?affected)
    (:assign ?query-type "decrease"))


(<< (get-query-type ?what ?affected ?query-type)
    (agent ?query ?what)
    (instance-of ?query ONT::INHIBIT)
    (affected ?query ?affected)
    (:assign ?query-type "inhibit"))

(<< (get-query-type ?what ?affected ?query-type)
    (agent ?query ?what)
    (instance-of ?query ONT::ACTIVATE)
    (affected ?query ?affected)
    (:assign ?query-type "activate"))

(<< (get-query-type ?what ?affected ?query-type)
    (agent ?query ?what)
    (instance-of ?query ONT::PHOSPHORYLATION)
    (affected ?query ?affected)
    (:assign ?query-type "phosphorylation"))

(<< (get-query-type ?what ?affected ?query-type)
    (agent ?query ?what)
    (instance-of ?query ONT::DEPHOSPHORYLATION)
    (affected ?query ?affected)
    (:assign ?query-type "dephosphorylation"))

(<< (get-query-type ?what ?affected ?query-type)
    (agent ?query ?what)
    (instance-of ?query ONT::MODULATE)
    (affected ?query ?affected)
    (:assign ?query-type "modulate"))


(<< (gene-for-what ?what ?gene)
    (suchthat ?what ?st)
    (neutral1 ?st ?tf)
    (or (assoc-with ?tf ?gene)
        (:assign ?gene ?tf))
    (instance-of ?gene ont::gene-protein))

(<< (gene-for-what ?what ?gene)
    (suchthat ?what ?st)
    (affected ?st ?gene)
    (instance-of ?gene ont::gene-protein))

