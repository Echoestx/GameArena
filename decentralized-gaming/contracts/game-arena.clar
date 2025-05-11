;; Game Arena Smart Contract - Version 1 (MVP)
;; Implementation for managing gaming tournaments

;; Error definitions
(define-constant ERROR-ACCESS-REJECTED (err u200))
(define-constant ERROR-TOURNEY-NOT-EXIST (err u201))
(define-constant ERROR-PLAYER-ALREADY-JOINED (err u202))
(define-constant ERROR-REGISTRATION-COMPLETE (err u203))
(define-constant ERROR-MATCH-NOT-EXIST (err u204))
(define-constant ERROR-MATCH-ALREADY-JUDGED (err u205))
(define-constant ERROR-TOURNEY-IN-PROGRESS (err u206))
(define-constant ERROR-TOURNEY-NOT-ACTIVE (err u207))
(define-constant ERROR-INVALID-PLAYER (err u208))
(define-constant ERROR-BAD-PARAMETER (err u216))

;; Tournament phases
(define-constant PHASE-REGISTRATION u0)
(define-constant PHASE-ACTIVE u1)
(define-constant PHASE-FINISHED u2)

;; Data structures
(define-map tourneys
  { tourney-id: uint }
  {
    name: (string-ascii 50),
    host: principal,
    phase: uint,
    entry-fee: uint,
    player-count: uint
  }
)

(define-map tourney-players
  { tourney-id: uint, player: principal }
  {
    joined-at: uint,
    score: uint,
    matches-played: uint
  }
)

(define-map matches
  { tourney-id: uint, match-id: uint }
  {
    player1: principal,
    player2: principal,
    winner: (optional principal),
    played-at: (optional uint)
  }
)

;; Store match counters per tournament
(define-map match-counters
  { tourney-id: uint }
  { counter: uint }
)

;; Global variables
(define-data-var tourney-counter uint u0)
(define-data-var system-manager principal tx-sender)

;; Permission checks
(define-private (is-system-manager)
  (is-eq tx-sender (var-get system-manager))
)

;; Permission check for tournament host
(define-private (is-tourney-host (tourney-id uint))
  (match (map-get? tourneys { tourney-id: tourney-id })
    tourney (is-eq tx-sender (get host tourney))
    false
  )
)

;; Get system manager (read-only function)
(define-read-only (get-system-manager)
  (var-get system-manager)
)

;; Update system manager
(define-public (update-system-manager (new-manager principal))
  (begin
    (asserts! (is-system-manager) ERROR-ACCESS-REJECTED)
    (asserts! (not (is-eq new-manager 'SP000000000000000000002Q6VF78)) ERROR-BAD-PARAMETER)
    (ok (var-set system-manager new-manager))
  )
)

;; Initiate a new tournament
(define-public (initiate-tourney
    (name (string-ascii 50))
    (entry-fee uint)
  )
  (let (
    (tourney-id (+ (var-get tourney-counter) u1))
  )
    ;; Input validation
    (asserts! (> (len name) u0) ERROR-BAD-PARAMETER)
    (asserts! (<= entry-fee u1000000000) ERROR-BAD-PARAMETER) ;; Max 1000 STX

    (map-set tourneys
      { tourney-id: tourney-id }
      {
        name: name,
        host: tx-sender,
        phase: PHASE-REGISTRATION,
        entry-fee: entry-fee,
        player-count: u0
      }
    )
    (var-set tourney-counter tourney-id)
    (ok tourney-id)
  )
)

;; Join a tournament
(define-public (join-tourney (tourney-id uint))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
    (entry-fee (get entry-fee tourney))
    (player-count (get player-count tourney))
  )
    (asserts! (is-eq (get phase tourney) PHASE-REGISTRATION) ERROR-REGISTRATION-COMPLETE)
    (asserts! (is-none (map-get? tourney-players { tourney-id: tourney-id, player: tx-sender })) ERROR-PLAYER-ALREADY-JOINED)
    
    ;; Handle entry fee if required
    (if (> entry-fee u0)
      (begin
        ;; Transfer fee to contract
        (unwrap! (stx-transfer? entry-fee tx-sender (as-contract tx-sender)) ERROR-BAD-PARAMETER)
        
        ;; Update player count
        (map-set tourneys
          { tourney-id: tourney-id }
          (merge tourney {
            player-count: (+ player-count u1)
          })
        )
      )
      ;; No fee, just update player count
      (map-set tourneys
        { tourney-id: tourney-id }
        (merge tourney { player-count: (+ player-count u1) })
      )
    )
    
    ;; Register player
    (map-set tourney-players
      { tourney-id: tourney-id, player: tx-sender }
      {
        joined-at: block-height,
        score: u0,
        matches-played: u0
      }
    )
    
    (ok true)
  )
)

;; Begin tournament
(define-public (begin-tourney (tourney-id uint))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
  )
    (asserts! (or (is-system-manager) (is-eq tx-sender (get host tourney))) ERROR-ACCESS-REJECTED)
    (asserts! (is-eq (get phase tourney) PHASE-REGISTRATION) ERROR-TOURNEY-IN-PROGRESS)
    (asserts! (>= (get player-count tourney) u2) ERROR-BAD-PARAMETER)
    
    ;; Update tournament phase
    (map-set tourneys
      { tourney-id: tourney-id }
      (merge tourney { phase: PHASE-ACTIVE })
    )
    
    (ok true)
  )
)

;; Get next match ID (helper)
(define-private (get-next-match-id (tourney-id uint))
  (let (
    (counter-data (default-to { counter: u0 } (map-get? match-counters { tourney-id: tourney-id })))
    (current-counter (get counter counter-data))
    (next-counter (+ current-counter u1))
  )
    ;; Update the counter
    (map-set match-counters
      { tourney-id: tourney-id }
      { counter: next-counter }
    )
    current-counter
  )
)

;; Schedule a match
(define-public (schedule-match (tourney-id uint) (player1 principal) (player2 principal))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
    (match-id (get-next-match-id tourney-id))
  )
    ;; Validate inputs
    (asserts! (not (is-eq player1 player2)) ERROR-INVALID-PLAYER)
    (asserts! (or (is-system-manager) (is-eq tx-sender (get host tourney))) ERROR-ACCESS-REJECTED)
    (asserts! (is-eq (get phase tourney) PHASE-ACTIVE) ERROR-TOURNEY-NOT-ACTIVE)
    (asserts! (is-some (map-get? tourney-players { tourney-id: tourney-id, player: player1 })) ERROR-INVALID-PLAYER)
    (asserts! (is-some (map-get? tourney-players { tourney-id: tourney-id, player: player2 })) ERROR-INVALID-PLAYER)
    
    ;; Create match
    (map-set matches
      { tourney-id: tourney-id, match-id: match-id }
      {
        player1: player1,
        player2: player2,
        winner: none,
        played-at: none
      }
    )
    
    (ok match-id)
  )
)

;; Record match result
(define-public (record-match-result (tourney-id uint) (match-id uint) (winner principal))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
    (match (unwrap! (map-get? matches { tourney-id: tourney-id, match-id: match-id }) ERROR-MATCH-NOT-EXIST))
    (player1 (get player1 match))
    (player2 (get player2 match))
    (player1-data (unwrap! (map-get? tourney-players { tourney-id: tourney-id, player: player1 }) ERROR-INVALID-PLAYER))
    (player2-data (unwrap! (map-get? tourney-players { tourney-id: tourney-id, player: player2 }) ERROR-INVALID-PLAYER))
  )
    ;; Validate inputs
    (asserts! (or (is-system-manager) (is-eq tx-sender (get host tourney))) ERROR-ACCESS-REJECTED)
    (asserts! (is-eq (get phase tourney) PHASE-ACTIVE) ERROR-TOURNEY-NOT-ACTIVE)
    (asserts! (is-none (get winner match)) ERROR-MATCH-ALREADY-JUDGED)
    (asserts! (or (is-eq winner player1) (is-eq winner player2)) ERROR-INVALID-PLAYER)
    
    ;; Update match
    (map-set matches
      { tourney-id: tourney-id, match-id: match-id }
      (merge match {
        winner: (some winner),
        played-at: (some block-height)
      })
    )
    
    ;; Update player stats
    (if (is-eq winner player1)
      (begin
        ;; Update player1 stats (winner)
        (map-set tourney-players
          { tourney-id: tourney-id, player: player1 }
          {
            joined-at: (get joined-at player1-data),
            score: (+ (get score player1-data) u3), ;; 3 points for winning
            matches-played: (+ (get matches-played player1-data) u1)
          }
        )
        ;; Update player2 stats (loser)
        (map-set tourney-players
          { tourney-id: tourney-id, player: player2 }
          {
            joined-at: (get joined-at player2-data),
            score: (+ (get score player2-data) u0), ;; 0 points for losing
            matches-played: (+ (get matches-played player2-data) u1)
          }
        )
      )
      (begin
        ;; Update player1 stats (loser)
        (map-set tourney-players
          { tourney-id: tourney-id, player: player1 }
          {
            joined-at: (get joined-at player1-data),
            score: (+ (get score player1-data) u0), ;; 0 points for losing
            matches-played: (+ (get matches-played player1-data) u1)
          }
        )
        ;; Update player2 stats (winner)
        (map-set tourney-players
          { tourney-id: tourney-id, player: player2 }
          {
            joined-at: (get joined-at player2-data),
            score: (+ (get score player2-data) u3), ;; 3 points for winning
            matches-played: (+ (get matches-played player2-data) u1)
          }
        )
      )
    )
    
    (ok true)
  )
)

;; End tournament
(define-public (end-tourney (tourney-id uint))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
  )
    (asserts! (or (is-system-manager) (is-eq tx-sender (get host tourney))) ERROR-ACCESS-REJECTED)
    (asserts! (is-eq (get phase tourney) PHASE-ACTIVE) ERROR-TOURNEY-NOT-ACTIVE)
    
    ;; Update tournament phase
    (map-set tourneys
      { tourney-id: tourney-id }
      (merge tourney { phase: PHASE-FINISHED })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-tourney (tourney-id uint))
  (map-get? tourneys { tourney-id: tourney-id })
)

(define-read-only (get-tourney-player (tourney-id uint) (player principal))
  (map-get? tourney-players { tourney-id: tourney-id, player: player })
)

(define-read-only (get-match (tourney-id uint) (match-id uint))
  (map-get? matches { tourney-id: tourney-id, match-id: match-id })
)

;; Initialize contract
(begin
  ;; Set system manager on deployment
  (var-set system-manager tx-sender)
)