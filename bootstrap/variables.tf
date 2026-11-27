variable "subscription_id" {
  description = "Subscription the landing zone is deployed into."
  type        = string
}

variable "location" {
  description = "Region for the state storage account."
  type        = string
  default     = "uksouth"
}

variable "project" {
  description = "Short lowercase project code used in names (letters and digits only)."
  type        = string
  default     = "lz"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.project))
    error_message = "project must be 2-6 lowercase letters or digits."
  }
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repo."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner, for repos using the immutable OIDC subject format (gh api repos/OWNER/REPO -q .owner.id). Leave null for the legacy owner/repo format."
  type        = number
  default     = null
}

variable "github_repo_id" {
  description = "Numeric ID of the GitHub repo, for repos using the immutable OIDC subject format (gh api repos/OWNER/REPO -q .id). Leave null for the legacy owner/repo format."
  type        = number
  default     = null
}

variable "github_environments" {
  description = "GitHub environments the apply identity trusts. Each needs required reviewers configured in GitHub."
  type        = list(string)
  default     = ["dev"]
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
