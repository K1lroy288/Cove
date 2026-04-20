package dto

import "encoding/json"

type User struct {
	ID       uint            `json:"id"`
	Username string          `json:"username"`
	Password string          `json:"password"`
	Settings json.RawMessage `json:"settings,omitempty"`
}
