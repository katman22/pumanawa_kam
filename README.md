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
