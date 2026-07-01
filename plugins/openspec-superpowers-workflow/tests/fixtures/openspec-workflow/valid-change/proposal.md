# Proposal: Add rate-limiting middleware

## Summary
Add per-IP rate limiting to the public API to prevent abuse.

## Motivation
Without rate limiting, a single client can exhaust server resources.
