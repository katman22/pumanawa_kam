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
longer used. Administrators have one product role: `super_admin` accesses both
products and user management; `canyon_admin` accesses Canyon resources only;
`mural_admin` accesses mural management only. Direct URLs enforce these boundaries
with HTTP 403; dashboard/layout navigation follows the same predicates.
There is no public signup, password recovery or generic permissions framework.

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
Admin::User.create!(username: username, password: password, password_confirmation: confirmation, role: :super_admin); nil
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

The Phase C role migration promotes existing administrators to `super_admin` to
preserve their access. New accounts default to `mural_admin`, never super admin;
choose the intended role explicitly. PostgreSQL enforces the allowed role values.
Only super admins can manage `/admin/users` (username, role, active status and
manual password changes). Blank password fields on edit retain the current
password. There is no user deletion route. Model updates cannot demote/deactivate
the final active super admin; a transaction-scoped PostgreSQL advisory lock
serializes these rare changes, including changes to different admin rows.

Parking creation is now POST, and Create/Update services require the authenticated
admin as actor. Existing updated_by text records admin ID and username, bounded
to the field's existing 120-character limit. Basic
environment credentials are no longer an audit identity. No new cross-domain FK.

The splash chooses one supplied local photograph per render; no rotation or
network interaction is needed to sign in. It retains the mirrored/right-aligned
Whare Pūmanawa mark and responsive uncropped image treatment. Originals are
temporary curated assets; delivery optimization can be reviewed separately.


## Whare Pūmanawa portfolio and administration

Preview the published portfolio at `/whare_pumanawa`; permalinks use
`/whare_pumanawa/murals/:slug`. No new production hostname is configured. Mural
admins and super admins manage content at `/admin/whare_pumanawa/murals` inside
the existing shared Bootstrap shell. Canyon-only admins cannot access these routes.

`WharePumanawa::Mural` and `WharePumanawa::MuralPhoto` use their own prefixed tables
in the existing primary database/migration stream. Order is position then id.
Slugs persist after title edits; normalized-title duplicates get distinct slugs,
and the unique index plus bounded savepoint retry handles creation collisions.
The first published mural is selected initially; each published slug selects its
own detail panel. All published details, photos/attachments/blobs and selector
buttons are server-rendered for this small V1. Stimulus switches panels locally,
with pressed state, focus management and Left/Right/Home/End navigation. All
gallery images load eagerly so selecting a mural makes no additional request;
this deliberately increases initial image delivery for a small portfolio. Mobile
selectors scroll horizontally. Permalinks and no-JavaScript links remain usable.

Create a draft, upload one or more JPEG/PNG/WebP photographs, then edit each
photo's alt text and numeric position. Equal positions use id order; the first
photo supplies the hero/thumbnail. Upload batches are validated together and
persist together; the upload form's initial alt text can be refined per photo.
Slug values are read-only in administration. Publishing uses the ordinary mural
form and shows photo validation errors. Unpublish before removing the final valid
photo. Photo removal and mural deletion use DELETE with UI confirmation; mural
deletion removes owned photos. Active Storage purges attachment bytes through
its existing background job adapter. Parent-row locks serialize publishing,
photo mutations and deletion through these controllers.

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

Deferred: drag/drop ordering, public production hostname, private attachment
delivery, durable production object-storage provisioning, richer permissions,
signup/recovery and gallery search/filtering. See
research/whare_pumanawa_phase_c_implementation.txt for Phase C validation and
research/whare_pumanawa_phase_b_implementation.txt for the storage foundation.

## Contributor showcases

Mural administrators and super admins manage contributors at
`/admin/whare_pumanawa/contributors`. Contributors are content identities, not
login accounts. Edit name, plain-text bio, location, order and active status;
slugs are permanent and deletion is not exposed. Assign contributors using the
ordinary mural form select. Deactivating a contributor hides their showcase,
while existing published mural detail URLs remain available.

Public showcases use `/whare_pumanawa/contributors/:slug`. They select up to ten
distinct attached originals from that contributor's published murals, taking
ordered hero photos before supporting photos. CSS Grid supplies the exhibition
wall; mobile uses an editorial stack. Existing image dimensions determine
landscape/portrait/squareish slots, with a neutral fallback when unavailable.
No synchronous analysis, new variants, layout JavaScript or storage changes.
Images link to existing mural permalinks; bio/story excerpts stay bounded.

Migration `20261016000001` adds the contributor table and nullable mural FK,
then assigns existing unassigned murals to an initial `Whare Pūmanawa`
contributor. Edit this placeholder's name/content and reassign murals as needed.
It creates no contributor when there are no existing unassigned murals.
The initial backfill preserves mural slugs, publication state, timestamps and
all attachment/storage records. The FK remains nullable and model association
optional during this rollout so old application writers remain compatible.
The admin form requires a contributor, but legacy requests can still omit it.
Once old writers are retired and assignments reviewed, repeat the unassigned
audit/backfill before a separate NOT NULL migration; no automatic post-deploy
backfill or NOT NULL enforcement is bundled here. R2 configuration is unchanged.

See research/whare_pumanawa_contributor_showcase.txt for inspection, exact files,
validation results and remaining rollout considerations.
