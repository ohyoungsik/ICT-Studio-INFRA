variable "name_prefix" {
  type = string
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true
}

variable "telegram_chat_id" {
  type      = string
  sensitive = true
}

variable "discord_webhook_url" {
  type      = string
  sensitive = true
}
