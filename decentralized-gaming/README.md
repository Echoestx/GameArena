# 🎮 GameArena Smart Contract

`GameArena.clar` is a Clarity-based smart contract built on the Stacks blockchain. It manages decentralized gaming competitions by enabling users to enroll, compete, and earn rewards based on their performance in head-to-head contests.

---

## ✨ Features

- **Competition Lifecycle Management**: Create, launch, and conclude structured competitions with defined parameters.
- **Enrollment**: Participants can enroll in competitions, optionally paying an entry fee.
- **Matchmaking and Contests**: Organizers or admins can create contests between two competitors, record outcomes, and assign victory points.
- **Reward Distribution**: After the competition concludes, the prize pool is distributed proportionally based on points earned.
- **Access Controls**: Differentiated permissions for admin and competition organizers.
- **Freezable Contract**: The admin can freeze/unfreeze the contract to prevent or allow changes/interactions.

---

## 🧱 Data Structures

### Competitions
Tracks metadata, organizer, stage, costs, and competitors.

### Contests
Represents a head-to-head matchup with victory tracking and timestamps.

### Competitors
Stores stats for each competitor: enrollment time, points, wins, etc.

### Rewards
Manages claim status and reward amounts post-competition.

---

## 🛠 Functions Overview

### Admin & Config
- `set-admin-account`: Change contract admin.
- `set-freeze`: Freeze/unfreeze the contract.

### Competition Management
- `create-competition`: Create a new competition.
- `launch-competition`: Start the competition.
- `conclude-competition`: End the competition after the finale block.

### Participation
- `enroll-in-competition`: Join a competition, paying entry cost if needed.

### Contest Management
- `create-contest`: Add a match between two competitors.
- `report-contest-outcome`: Declare a winner, update stats and points.

### Rewards
- `calculate-reward`: Check potential reward for a competitor.
- `collect-reward`: Claim your earnings after competition conclusion.

### Read-only
- `get-competition`, `get-contest`, `get-last-contest-id`
- `get-total-points`, `get-competition-competitor`
- `get-competitor-contests`, `get-competitor-ranking`
- `get-admin-account`, `get-scoreboard` (stub), etc.

---

## 🛡 Error Codes

| Code | Description |
|------|-------------|
| `100` | Permission Denied |
| `101` | Competition Not Found |
| `102` | Already Enrolled |
| `103` | Enrollment Closed |
| `104` | Contest Not Found |
| `105` | Contest Already Scored |
| ...  | See contract for full list |

---

## 📌 Notes

- **Scalability**: Functions like `get-competitor-contests` are capped at 10 contests for simplicity.
- **Scoreboard** and **Full Competitor Lists** are not fully implemented and would require external indexing or map extension support.
