# Environment
OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
KEYS_DIR="${OCFR_DIR}/keys"
REPORTS_DIR="${OCFR_DIR}/reports"
SENT_DIR="${OCFR_DIR}/sent"

# Default configuration
DEFAULT_REPO="https://github.com/bobosdaddy/claw-friends-data"
MAX_RETRIES=3
AFFINITY_THRESHOLD=70
ABANDON_THRESHOLD=30
MAX_ROUNDS=10

# Crypto settings
RSA_KEY_SIZE=2048
AES_CIPHER="aes-256-cbc"
RSA_OAEP_MD="sha256"
