require "pagy/extras/metadata"  # adds pagy_metadata helper for JSON responses
require "pagy/extras/overflow"  # returns last page instead of raising on out-of-bounds

Pagy::DEFAULT[:limit]    = 25
Pagy::DEFAULT[:overflow] = :last_page
