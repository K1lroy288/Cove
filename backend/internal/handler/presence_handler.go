package handler

import (
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// GetPresence godoc
// GET /user/presence?ids=1,2,3
// Возвращает map[userID]isOnline для переданных ID.
func GetPresence(hub *AppHub) gin.HandlerFunc {
	return func(ctx *gin.Context) {
		idsParam := ctx.Query("ids")
		if idsParam == "" {
			ctx.JSON(200, gin.H{})
			return
		}
		var userIDs []uint
		for _, s := range strings.Split(idsParam, ",") {
			s = strings.TrimSpace(s)
			if s == "" {
				continue
			}
			id, err := strconv.ParseUint(s, 10, 64)
			if err == nil {
				userIDs = append(userIDs, uint(id))
			}
		}
		ctx.JSON(200, hub.IsOnlineMany(userIDs))
	}
}
