# Kam's Tikanga(knowledge)

Various applications 

##### Prerequisites

The setup steps expect the following tools are installed on the system.

- Github
- Ruby [3.3.0](https://www.ruby-lang.org/en/news/2023/12/25/ruby-3-3-0-released/)
- Rails [8.0.2](https://rubyonrails.org/2025/3/12/Rails-Version-8-0-2-has-been-released)


## Shared web administration

`/admin/login` is the Whare Pūmanawa splash and ordinary HTML login. `/admin`
is the shared dashboard; existing resort/camera/filter/parking routes remain.
Web admins use `Admin::User` / `admin_users`; mobile `User`, identities, JWTs and
entitlements remain separate. HTTP Basic and ADMIN_USER/ADMIN_PASSWORD are no
longer used. All active web admins have access to the existing admin resources.
No signup, recovery, roles, account editing, murals or gallery are added here.

Run the new migration, then create the first admin in the intended environment's
Rails console. Use only the pumanawa_kam database intended for that environment:
for production, run `RAILS_ENV=production bin/rails console` in the existing Render
application runtime after deployment migrations, then enter the following prompts.

```ruby
require "io/console"
print "Username: "
username = STDIN.gets.chomp
password = STDIN.getpass("Password (12+ characters): "); nil
confirmation = STDIN.getpass("Confirm password: "); nil
Admin::User.create!(username: username, password: password, password_confirmation: confirmation); nil
password = confirmation = nil
```

The prompt hides passwords and trailing nil prevents console echo. Never enter
real passwords as command literals, commit them or seed a default credential.
No production account is created automatically. Usernames are stripped/lowercased;
passwords require at least 12 characters and at most 72 bytes (bcrypt's limit).
Passwords are bcrypt hashes. Rails' encrypted cookie holds only admin_user_id,
with its ordinary CSRF protections and production HTTPS. Cookie key/domain are
unchanged; no cross-domain SSO or JWT-to-admin authentication is introduced.
Login resets the session; logout clears it. That also clears forecast recent
locations on the same browser/host. Deactivation rejects subsequent admin access:
`admin.update!(active: false)`. Password changes do not invalidate other browser
sessions; logout clears the current browser only. Login attempts are limited to
10 per IP per three minutes in process-local memory, not across workers/restarts.

Parking creation is now POST, and Create/Update services require the authenticated
admin as actor. Existing updated_by text records admin ID and username, bounded
to the field's existing 120-character limit. Basic
environment credentials are no longer an audit identity. No new cross-domain FK.

The splash chooses one supplied local photograph per render; no rotation or
network interaction is needed to sign in. It retains the mirrored/right-aligned
Whare Pūmanawa mark and responsive uncropped image treatment. Originals are
temporary curated assets; delivery optimization can be reviewed separately.


## Whare Pūmanawa public foundation (Phase B)

Preview the published portfolio at `/whare_pumanawa`; permalinks use
`/whare_pumanawa/murals/:slug`. No new production hostname or mural admin CRUD
exists yet. `/admin` links to the foundation and marks mural administration as
coming next. No changes to web-admin or mobile authentication are needed here.

`WharePumanawa::Mural` and `WharePumanawa::MuralPhoto` use their own prefixed tables
in the existing primary database/migration stream. Order is position then id.
Slugs persist after title edits; normalized-title duplicates get distinct slugs,
and the unique index plus bounded savepoint retry handles creation collisions.
The first published mural is selected initially; each published slug selects its
own detail page. All photos/attachments/blobs are preloaded for this small V1.
There is no final selector interaction yet; navigation uses ordinary links.

Drafts may have incomplete photos. Publication requires at least one photo and
every photo must have an attached supported image plus nonblank descriptive alt
text. Public rendering also omits photos that later become invalid. Description
is treated as escaped plain text, with paragraphs preserved. Originals remain
stored; named variants are thumbnail (240x180 fill/crop) and hero (fit within
1600x1600, preserving aspect ratio and avoiding upscaling). Only JPEG, PNG and
WebP are accepted, up to 20 MiB. The first valid ordered photo supplies the hero.

Active Storage's standard three tables are installed once. Development uses
local Disk and test uses test Disk, as configured before Phase B. Install native
libvips for development/runtime; the local build is currently 8.18.7 and Rails
uses `config.active_storage.variant_processor = :vips`. Real fixture processing
and variant HTTP delivery are covered in tests; no image-processing stubs.

Production mural images explicitly select the `mural_artwork` S3-compatible
service through Rails' per-attachment service selector. This is separate from
the shared application's existing global storage setting. The selector defers
service construction until attachment use so absent future bucket credentials
do not break other application domains during eager loading. There is no Disk
fallback for production mural uploads. Supply these runtime settings before
uploading artwork in production; placeholders create no infrastructure:

- MURAL_STORAGE_BUCKET
- MURAL_STORAGE_REGION (default us-east-1)
- MURAL_STORAGE_ACCESS_KEY_ID
- MURAL_STORAGE_SECRET_ACCESS_KEY
- MURAL_STORAGE_ENDPOINT if using an S3-compatible provider instead of AWS S3

Keep originals in durable object storage, never the ephemeral Render web disk.
Back up originals and the database; derivatives can be regenerated. Do not copy
local/test blob records into production without moving their originals and
mapping service names. No bucket, credentials, Render service changes, direct
upload UI or dedicated worker was provisioned. Standard Rails analysis/purge jobs
use the existing job adapter; production durability of those jobs remains a
deployment consideration before enabling live uploads. Signed Active Storage
URLs are not private draft authorization; private delivery remains deferred.

Phase C: mural admin CRUD, photo upload/edit/order forms, publishing workflow,
and the final gallery selector/detail interaction. See
research/whare_pumanawa_phase_b_implementation.txt for validation and limitations.
