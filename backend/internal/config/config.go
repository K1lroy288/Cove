package config

import (
	"os"
	"sync"

	_ "github.com/joho/godotenv/autoload"
)

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

type Config struct {
	Port      string
	JwtSecret string
	DB        DBConfig
	MinIO     MinIOConfig
}

type DBConfig struct {
	Host     string
	User     string
	Password string
	Name     string
	Port     string
}

type MinIOConfig struct {
	Endpoint  string
	AccessKey string
	SecretKey string
	Bucket    string
	PublicURL string
	UseSSL    bool
}

var (
	instance *Config
	once     sync.Once
)

func GetConfig() *Config {
	if instance == nil {
		return loadConfig()
	}

	return instance
}

func loadConfig() *Config {
	once.Do(func() {
		instance = &Config{
			Port:      os.Getenv("APP_PORT"),
			JwtSecret: os.Getenv("JWT_SECRET"),
			DB: DBConfig{
				Host:     os.Getenv("DB_HOST"),
				User:     os.Getenv("DB_USER"),
				Password: os.Getenv("DB_PASSWORD"),
				Name:     os.Getenv("DB_NAME"),
				Port:     os.Getenv("DB_PORT"),
			},
			MinIO: MinIOConfig{
				Endpoint:  envOrDefault("MINIO_ENDPOINT", "localhost:9000"),
				AccessKey: envOrDefault("MINIO_ACCESS_KEY", "minioadmin"),
				SecretKey: envOrDefault("MINIO_SECRET_KEY", "minioadmin"),
				Bucket:    envOrDefault("MINIO_BUCKET", "cove-media"),
				PublicURL: envOrDefault("MINIO_PUBLIC_URL", "http://localhost:9000"),
				UseSSL:    os.Getenv("MINIO_USE_SSL") == "true",
			},
		}
	})

	return instance
}
