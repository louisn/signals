package api

import (
	"context"
	"net/http"
	"strings"
)

type contextKey string

const deviceIDContextKey contextKey = "device_id"
const adminKeyHeader = "X-Admin-Key"

func bearerToken(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(h, prefix) {
		return "", false
	}
	return strings.TrimPrefix(h, prefix), true
}

// deviceAuth validates the bearer token against the device_id claimed in
// the request body's device_id field, which handlers read after this
// middleware has stashed the raw token in the request context.
func (s *Server) deviceAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok || token == "" {
			writeError(w, http.StatusUnauthorized, "missing_bearer_token")
			return
		}
		ctx := context.WithValue(r.Context(), deviceIDContextKey, token)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func tokenFromContext(ctx context.Context) string {
	tok, _ := ctx.Value(deviceIDContextKey).(string)
	return tok
}

// adminAuth protects device-provisioning endpoints with a static admin key,
// never exposed to the shipped app.
func (s *Server) adminAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.adminKey == "" || r.Header.Get(adminKeyHeader) != s.adminKey {
			writeError(w, http.StatusUnauthorized, "invalid_admin_key")
			return
		}
		next.ServeHTTP(w, r)
	})
}
