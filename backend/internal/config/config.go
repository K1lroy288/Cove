package config

import (
	"os"
	"sync"

	_ "github.com/joho/godotenv/autoload"
)

type Config struct {
	AppHost   string
	AppPort   string
	JwtSecret string
}

var (
	instance *Config
	once     sync.Once
)

func loadConfig() *Config {
	once.Do(func() {
		instance = &Config{
			AppHost:   os.Getenv("APP_HOST"),
			AppPort:   os.Getenv("APP_PORT"),
			JwtSecret: os.Getenv("JWT_SECRET"),
		}
	})

	return instance
}

func GetConfig() *Config {
	if instance == nil {
		return loadConfig()
	}

	return instance
}
