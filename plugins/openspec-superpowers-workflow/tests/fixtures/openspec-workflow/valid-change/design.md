# Design: Rate-limiting middleware

## Architecture
Use a token-bucket algorithm backed by Redis for distributed rate limiting.

## Components
- `RateLimiter` class in `src/middleware/rate-limiter.ts`
- Redis key: `rl:{ip}:{window}`
