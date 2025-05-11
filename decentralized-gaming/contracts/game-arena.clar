;; Game Arena Smart Contract - Version 2 
;; Implementation with extended features and validations

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
(define-constant ERROR-FUNDS-TOO-LOW (err u209))
(define-constant ERROR-PRIZE-ALREADY-TAKEN (err u210))
(define-constant ERROR-NOT-ELIGIBLE (err u211))
(define-constant ERROR-INVALID-PHASE (err u212))
(define-constant ERROR-TOURNEY-ENDED (err u213))
(define-constant ERROR-TOURNEY-NOT-ENDED (err u215))
(define-constant ERROR-SYSTEM-LOCKED (err u214))
(define-constant ERROR-BAD-PARAMETER (err u216))
(define-constant ERROR-BAD-NAME (err u217))
(define-constant ERROR-BAD-DESCRIPTION (err u218))
(define-constant ERROR-BAD-ENTRY-FEE (err u219))
(define-constant ERROR-BAD-DURATION (err u220))
(define-constant ERROR-BAD-START-HEIGHT (err u221))
(define-constant ERROR-BAD-PLAYER-CAP (err u222))
(define-constant ERROR-TOO-FEW-PLAYERS (err u223))
(define-constant ERROR-TOURNEY-ONGOING (err u224))
(define-constant ERROR-BAD-TOURNEY-ID (err u225))
(define-constant ERROR-BAD-MATCH-ID (err u226))
(define-constant ERROR-BAD-ROUND (err u227))

;; Tournament phases
(define-constant PHASE-REGISTRATION u0)
(define-constant PHASE-ACTIVE u1)
(define-constant PHASE-FINISHED u2)

;; Data structures
(define-map tourneys
  { tourney-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 255),
    host: principal,
    phase: uint,
    entry-fee: uint,
    prize-pool: uint,
    start-height: uint,
    end-height: uint,
    player-cap: uint,
    player-count: uint
  }
)

(define-map tourney-players
  { tourney-id: uint, player: principal }
  {
    joined-at: uint,
    score: uint,
    matches-played: uint,
    matches-won: uint
  }
)

(define-map matches
  { tourney-id: uint, match-id: uint }
  {
    player1: principal,
    player2: principal,
    winner: (optional principal),
    played-at: (optional uint),
    round: uint
  }
)

(define-map prize-claims
  { tourney-id: uint, player: principal }
  { claimed: bool, amount: uint }
)

;; Track total score for each tournament
(define-map tourney-scores
  { tourney-id: uint }
  { total-score: uint }
)

;; Store match counters per tournament
(define-map match-counters
  { tourney-id: uint }
  { counter: uint }
)

;; Global variables
(define-data-var tourney-counter uint u0)
(define-data-var system-manager principal tx-sender)
(define-data-var system-locked bool false)

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

;; Validation check for tournament existence
(define-private (tourney-exists (tourney-id uint))
  (is-some (map-get? tourneys { tourney-id: tourney-id }))
)

;; Check if system is locked
(define-private (verify-system-active)
  (not (var-get system-locked))
)

;; Validate tournament ID
(define-private (validate-tourney-id (tourney-id uint))
  (if (<= tourney-id (var-get tourney-counter))
    true
    false
  )
)

;; Validate match ID
(define-private (validate-match-id (tourney-id uint) (match-id uint))
  (let ((counter-data (default-to { counter: u0 } (map-get? match-counters { tourney-id: tourney-id }))))
    (< match-id (get counter counter-data))
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
    ;; Validate new manager is not null principal
    (asserts! (not (is-eq new-manager 'SP000000000000000000002Q6VF78)) ERROR-BAD-PARAMETER)
    (ok (var-set system-manager new-manager))
  )
)

;; Lock/unlock system
(define-public (toggle-system-lock (lock-status bool))
  (begin
    (asserts! (is-system-manager) ERROR-ACCESS-REJECTED)
    (ok (var-set system-locked lock-status))
  )
)

;; Initiate a new tournament
(define-public (initiate-tourney
    (name (string-ascii 50))
    (description (string-ascii 255))
    (entry-fee uint)
    (start-height uint)
    (end-height uint)
    (player-cap uint)
  )
  (let (
    (tourney-id (+ (var-get tourney-counter) u1))
  )
    (asserts! (verify-system-active) ERROR-SYSTEM-LOCKED)
    
    ;; Input validation
    (asserts! (> (len name) u0) ERROR-BAD-NAME)
    (asserts! (> (len description) u0) ERROR-BAD-DESCRIPTION)
    ;; Validate entry fee - can be 0 or positive value with reasonable limit
    (asserts! (<= entry-fee u1000000000) ERROR-BAD-ENTRY-FEE) ;; Max 1000 STX
    (asserts! (< start-height end-height) ERROR-BAD-DURATION)
    (asserts! (>= start-height block-height) ERROR-BAD-START-HEIGHT)
    (asserts! (> player-cap u1) ERROR-BAD-PLAYER-CAP)

    (map-set tourneys
      { tourney-id: tourney-id }
      {
        name: name,
        description: description,
        host: tx-sender,
        phase: PHASE-REGISTRATION,
        entry-fee: entry-fee,
        prize-pool: u0,
        start-height: start-height,
        end-height: end-height,
        player-cap: player-cap,
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
    (player-cap (get player-cap tourney))
  )
    ;; Validate tournament ID
    (asserts! (validate-tourney-id tourney-id) ERROR-BAD-TOURNEY-ID)
    (asserts! (verify-system-active) ERROR-SYSTEM-LOCKED)
    (asserts! (is-eq (get phase tourney) PHASE-REGISTRATION) ERROR-REGISTRATION-COMPLETE)
    (asserts! (< player-count player-cap) ERROR-REGISTRATION-COMPLETE)
    (asserts! (is-none (map-get? tourney-players { tourney-id: tourney-id, player: tx-sender })) ERROR-PLAYER-ALREADY-JOINED)
    
    ;; Handle entry fee if required
    (if (> entry-fee u0)
      (begin
        ;; Transfer fee to contract
        (unwrap! (stx-transfer? entry-fee tx-sender (as-contract tx-sender)) ERROR-FUNDS-TOO-LOW)
        
        ;; Update prize pool
        (map-set tourneys
          { tourney-id: tourney-id }
          (merge tourney {
            prize-pool: (+ (get prize-pool tourney) entry-fee),
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
        matches-played: u0,
        matches-won: u0
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
    ;; Validate tournament ID
    (asserts! (validate-tourney-id tourney-id) ERROR-BAD-TOURNEY-ID)
    (asserts! (verify-system-active) ERROR-SYSTEM-LOCKED)
    (asserts! (or (is-system-manager) (is-eq tx-sender (get host tourney))) ERROR-ACCESS-REJECTED)
    (asserts! (is-eq (get phase tourney) PHASE-REGISTRATION) ERROR-TOURNEY-IN-PROGRESS)
    (asserts! (>= (get player-count tourney) u2) ERROR-TOO-FEW-PLAYERS)
    
    ;; Update tournament phase
    (map-set tourneys
      { tourney-id: tourney-id }
      (merge tourney { phase: PHASE-ACTIVE }      )
    )
    
    (ok true)
  )
)

;; End tournament
(define-public (end-tourney (tourney-id uint))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
  )
    ;; Validate tournament ID
    (asserts! (validate-tourney-id tourney-id) ERROR-BAD-TOURNEY-ID)
    (asserts! (verify-system-active) ERROR-SYSTEM-LOCKED)
    (asserts! (or (is-system-manager) (is-eq tx-sender (get host tourney))) ERROR-ACCESS-REJECTED)
    (asserts! (is-eq (get phase tourney) PHASE-ACTIVE) ERROR-TOURNEY-NOT-ACTIVE)
    (asserts! (>= block-height (get end-height tourney)) ERROR-TOURNEY-ONGOING)
    
    ;; Update tournament phase
    (map-set tourneys
      { tourney-id: tourney-id }
      (merge tourney { phase: PHASE-FINISHED })
    )
    
    (ok true)
  )
)

;; Get total points of all players in a tournament
(define-read-only (get-tourney-points (tourney-id uint))
  (get total-score (default-to { total-score: u0 } (map-get? tourney-scores { tourney-id: tourney-id })))
)

;; Calculate prize for a player
(define-read-only (calculate-prize (tourney-id uint) (player principal))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
    (player-data (unwrap! (map-get? tourney-players { tourney-id: tourney-id, player: player }) ERROR-INVALID-PLAYER))
    (prize-pool (get prize-pool tourney))
    (player-count (get player-count tourney))
    (player-score (get score player-data))
  )
    (asserts! (is-eq (get phase tourney) PHASE-FINISHED) ERROR-TOURNEY-NOT-ENDED)
    
    ;; Simple prize calculation - proportional to player's score
    (if (> player-score u0)
      (let (
        (total-points (get-tourney-points tourney-id))
        (prize-share (/ (* prize-pool player-score) total-points))
      )
        (ok prize-share)
      )
      (ok u0)
    )
  )
)

;; Claim prize
(define-public (claim-prize (tourney-id uint))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
    (player-data (unwrap! (map-get? tourney-players { tourney-id: tourney-id, player: tx-sender }) ERROR-INVALID-PLAYER))
    (prize-claim (default-to { claimed: false, amount: u0 } (map-get? prize-claims { tourney-id: tourney-id, player: tx-sender })))
    (prize-amount (unwrap! (calculate-prize tourney-id tx-sender) ERROR-NOT-ELIGIBLE))
  )
    ;; Validate tournament ID
    (asserts! (validate-tourney-id tourney-id) ERROR-BAD-TOURNEY-ID)
    (asserts! (verify-system-active) ERROR-SYSTEM-LOCKED)
    (asserts! (is-eq (get phase tourney) PHASE-FINISHED) ERROR-TOURNEY-NOT-ENDED)
    (asserts! (not (get claimed prize-claim)) ERROR-PRIZE-ALREADY-TAKEN)
    (asserts! (> prize-amount u0) ERROR-NOT-ELIGIBLE)
    
    ;; Mark prize as claimed
    (map-set prize-claims
      { tourney-id: tourney-id, player: tx-sender }
      { claimed: true, amount: prize-amount }
    )
    
    ;; Transfer prize to player
    (unwrap! (as-contract (stx-transfer? prize-amount (as-contract tx-sender) tx-sender)) ERROR-FUNDS-TOO-LOW)
    
    (ok prize-amount)
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

;; Check if a player is in a match
(define-private (is-player-in-match? (player principal) (match-data {player1: principal, player2: principal, winner: (optional principal), played-at: (optional uint), round: uint}))
  (or (is-eq player (get player1 match-data))
      (is-eq player (get player2 match-data)))
)

;; Get player's matches
(define-read-only (get-player-matches (tourney-id uint) (player principal))
  ;; Simplified version that checks first 5 match IDs
  (filter-matches-id-0 tourney-id player)
)

;; Check each match ID individually (avoiding recursion)
(define-private (filter-matches-id-0 (tourney-id uint) (player principal))
  (let ((match-data-0 (map-get? matches { tourney-id: tourney-id, match-id: u0 }))
        (match-data-1 (map-get? matches { tourney-id: tourney-id, match-id: u1 }))
        (match-data-2 (map-get? matches { tourney-id: tourney-id, match-id: u2 }))
        (match-data-3 (map-get? matches { tourney-id: tourney-id, match-id: u3 }))
        (match-data-4 (map-get? matches { tourney-id: tourney-id, match-id: u4 }))
        (result-0 (if (and (is-some match-data-0) 
                         (is-player-in-match? player (unwrap-panic match-data-0)))
                   (list u0)
                   (list)))
        (result-1 (if (and (is-some match-data-1)
                         (is-player-in-match? player (unwrap-panic match-data-1)))
                   (append result-0 u1)
                   result-0))
        (result-2 (if (and (is-some match-data-2)
                         (is-player-in-match? player (unwrap-panic match-data-2)))
                   (append result-1 u2)
                   result-1))
        (result-3 (if (and (is-some match-data-3)
                         (is-player-in-match? player (unwrap-panic match-data-3)))
                   (append result-2 u3)
                   result-2))
        (result-4 (if (and (is-some match-data-4)
                         (is-player-in-match? player (unwrap-panic match-data-4)))
                   (append result-3 u4)
                   result-3))
       )
    result-4
  )
)

;; Initialize contract
(begin
  ;; Set system manager on deployment
  (var-set system-manager tx-sender)
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
(define-public (schedule-match (tourney-id uint) (player1 principal) (player2 principal) (round uint))
  (let (
    (tourney (unwrap! (map-get? tourneys { tourney-id: tourney-id }) ERROR-TOURNEY-NOT-EXIST))
    (match-id (get-next-match-id tourney-id))
  )
    ;; Validate inputs
    (asserts! (validate-tourney-id tourney-id) ERROR-BAD-TOURNEY-ID)
    (asserts! (> round u0) ERROR-BAD-ROUND)
    (asserts! (not (is-eq player1 player2)) ERROR-INVALID-PLAYER)
    (asserts! (verify-system-active) ERROR-SYSTEM-LOCKED)
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
        played-at: none,
        round: round
      }
    )
    
    (ok match-id)
  )
)

;; Get last match ID (read-only)
(define-read-only (get-latest-match-id (tourney-id uint))
  (get counter (default-to { counter: u0 } (map-get? match-counters { tourney-id: tourney-id })))
)
