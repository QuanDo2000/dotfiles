# Global Agent Instructions

## Code Search

Use codebase-memory first when it is available for code discovery, symbol definitions, call relationships, and architecture; run `index_repository` first if needed. If codebase-memory is unavailable or cannot answer the query, fall back to FFF for filename and text search instead of grep, glob, or find.
