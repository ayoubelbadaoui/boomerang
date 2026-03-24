# Boomerang — Architecture Guidelines

> **Single source of truth** for all development and AI-assisted refactoring.
> Based on analysis of the existing codebase, prioritising patterns already working well.

---

## 1. Overview

Boomerang is a Flutter social-media app (short-form video / "boomerang" sharing) backed by Firebase. The architecture follows a **feature-first, layered** approach with four layers per feature:

| Layer | Purpose |
|---|---|
| **domain** | Pure-Dart entities, value objects, failures, repository interfaces |
| **infrastructure** | Firebase/API implementations of domain interfaces, DTOs |
| **application** | Controllers, notifiers, use-case orchestration, Riverpod providers |
| **presentation** | Screens, pages, widgets — UI only |

**State management:** Riverpod (manual providers, no code-gen currently).
**Navigation:** GoRouter with auth-aware redirects.
**Backend:** Firebase (Auth, Firestore, Storage, Messaging).

---

## 2. Project Structure

```
lib/
├── main.dart                       # Bootstrap, Firebase init, network check
├── app.dart                        # MaterialApp.router, ScreenUtil, theme
├── router.dart                     # GoRouter config + auth redirect
├── firebase_options.dart           # Generated — do not edit
│
├── core/
│   ├── assets/
│   │   └── shared_assets.dart      # Centralised asset path constants
│   ├── notifications/
│   │   └── push_notifications_service.dart
│   ├── theme/
│   │   └── app_theme.dart          # buildAppTheme() — single source for ThemeData
│   ├── utils/
│   │   ├── auth_error_mapper.dart  # Firebase error → user-facing string
│   │   ├── color_opacity.dart      # Color.fade() extension
│   │   ├── firestore_paths.dart    # Centralised Firestore path helpers (FP)
│   │   └── validators.dart         # Form validators
│   └── widgets/                    # Global reusable widgets
│       ├── ui.dart                 # Barrel export
│       ├── avatar.dart
│       ├── boomerang_overlay.dart
│       ├── input_filled.dart
│       ├── primary_button.dart
│       ├── section_divider.dart
│       └── social_button.dart
│
├── infrastructure/
│   └── providers.dart              # Firebase instance providers + cross-cutting providers
│
└── features/
    ├── auth/
    │   ├── domain/                 # AuthUser (freezed), AuthState, username validation
    │   ├── infrastructure/         # AuthRepo (abstract), FirebaseAuthRepo
    │   ├── application/            # AuthController (StateNotifier)
    │   └── presentation/           # Login, Signup, Onboarding, Setup pages
    │       └── widgets/            # Feature-local widgets (SocialAuthButton)
    │
    ├── feed/
    │   ├── infrastructure/         # BoomerangRepo, CommentsRepo, LikesRepo, etc.
    │   └── presentation/           # HomeTabs, Editor, Sheets, Viewer pages
    │       ├── editor/
    │       ├── sheets/
    │       ├── tabs/
    │       └── widgets/
    │
    ├── profile/
    │   ├── domain/                 # UserProfile, AppSettings, FollowPrivacy
    │   ├── infrastructure/         # FollowRepo, UserProfileRepo, SettingsRepo, etc.
    │   ├── application/            # ProfileController, SettingsController, etc.
    │   └── presentation/           # Profile, OtherUser, Settings pages
    │       ├── settings/
    │       ├── sheets/
    │       └── widgets/
    │
    └── splash_screen/
        └── presentation/           # SplashScreen
```

---

## 3. Layer Responsibilities

### 3.1 Domain

The domain layer is the **innermost ring**. It has zero external dependencies.

| CAN | MUST NOT |
|---|---|
| Define entities and value objects | Import Flutter, Firebase, or any third-party SDK |
| Define repository interfaces (abstract classes) | Depend on infrastructure, application, or presentation |
| Define failures / error types | Hold any state-management code (Riverpod, etc.) |
| Contain pure functions and validation logic | Perform I/O or side-effects |

**Reference model:** `features/auth/domain/` and `features/profile/domain/follow_privacy.dart` — pure Dart, easily testable.

### 3.2 Infrastructure

Implements domain interfaces. The **only** layer that touches Firebase, REST APIs, local storage, or any I/O.

| CAN | MUST NOT |
|---|---|
| Import and use Firebase SDKs | Contain business rules or domain logic |
| Implement abstract repository interfaces from domain | Be imported by presentation directly |
| Define DTOs and mapping functions | Import Flutter widgets or UI code |
| Throw typed failures defined in domain | Depend on application or presentation |

**Reference model:** `features/auth/infrastructure/` — `AuthRepo` (abstract in infra) + `FirebaseAuthRepo` (concrete).

### 3.3 Application

Orchestrates business logic. Bridges domain and presentation via Riverpod providers.

| CAN | MUST NOT |
|---|---|
| Define Riverpod providers and controllers | Import Flutter widgets or UI code |
| Call repository interfaces (from domain) | Call Firebase or APIs directly |
| Coordinate multiple use cases | Contain presentation / routing logic |
| Transform domain data for the UI | Expose infrastructure types (e.g. `QueryDocumentSnapshot`) |

**Reference model:** `features/auth/application/auth_controller.dart` — clean `StateNotifier` that delegates to `AuthRepo`.

### 3.4 Presentation

Pure UI. Consumes providers from application; renders state.

| CAN | MUST NOT |
|---|---|
| Build widgets and screens | Contain business logic or data-fetching orchestration |
| Read / watch Riverpod providers | Call repositories or Firebase directly |
| Dispatch actions to controllers | Define or expose providers (those belong in application) |
| Use `Theme.of(context)` for styling | Use hardcoded colors, text styles, or magic numbers |

---

## 4. Dependency Rules

```
presentation  →  application  →  domain  ←  infrastructure
     ↓               ↓                          ↑
     └─── core (theme, widgets, utils) ─────────┘
```

### Allowed imports

| From | May import |
|---|---|
| **presentation** | application, domain, core |
| **application** | domain, core |
| **infrastructure** | domain, core |
| **domain** | Nothing (pure Dart only; core/utils if pure Dart) |
| **core** | Only Flutter SDK + pure Dart packages |

### Forbidden dependencies

| Rule | Reason |
|---|---|
| presentation → infrastructure | UI must never touch Firebase/API directly |
| application → infrastructure | Application depends on domain interfaces, not concrete repos |
| domain → anything | Domain stays pure and portable |
| core → features | Core is shared foundation; features depend on core, never the reverse |
| feature A → feature B | Features do not import each other; share via core abstractions or the central provider file |

---

## 5. Feature Structure Template

When adding a new feature, scaffold it as:

```
features/<feature_name>/
├── domain/
│   ├── <entity>.dart              # Immutable entity (freezed or manual)
│   ├── <entity>_failure.dart      # Typed failures
│   └── <feature>_repo.dart        # Abstract repository interface
│
├── infrastructure/
│   ├── firebase_<feature>_repo.dart  # Concrete Firebase implementation
│   └── <entity>_dto.dart             # DTO / mapping (if needed)
│
├── application/
│   ├── <feature>_controller.dart     # StateNotifier / AsyncNotifier
│   └── <feature>_providers.dart      # All providers for this feature
│
└── presentation/
    ├── <feature>_page.dart           # Top-level page / screen
    └── widgets/
        ├── <component>_widget.dart   # Feature-local reusable widgets
        └── ...
```

### Checklist for new features

1. Define entities and repo interface in `domain/`.
2. Implement the repo in `infrastructure/` using Firebase/API.
3. Create controllers and providers in `application/`.
4. Build UI in `presentation/`, consuming providers only.
5. Extract reusable pieces to `presentation/widgets/` or `core/widgets/`.
6. Run `flutter analyze` to verify no layer violations.

---

## 6. Widget Architecture Rules

### 6.1 Widget classification

| Type | Location | Example |
|---|---|---|
| **Global reusable** | `core/widgets/` | `PrimaryButton`, `InputFilled`, `AppAvatar`, `SectionDivider` |
| **Feature-local reusable** | `features/<f>/presentation/widgets/` | `SocialAuthButton`, `Badge`, `PostsGrid`, `Stat` |
| **Screen / page** | `features/<f>/presentation/` | `LoginPage`, `SettingsPage`, `HomeShell` |
| **Sheet / dialog** | `features/<f>/presentation/sheets/` | `CommentsSheet`, `FollowListSheet` |

### 6.2 Size limits

| Guideline | Threshold |
|---|---|
| Max lines per widget file | **200 lines** (hard target) |
| Decompose at | **150 lines** (soft trigger to start extracting) |
| God-widget threshold | **300+ lines** — must be refactored |

### 6.3 Composition rules

- **One widget = one responsibility.** If a widget handles layout AND data fetching AND user interaction, split it.
- **Extract repeated UI patterns** (e.g., setting rows, stat displays, action buttons) into named widgets.
- **Page widgets** should be a thin scaffold that composes smaller widgets.
- **No inline anonymous widget trees deeper than 3 levels** — extract to a named widget or helper method.

### 6.4 Existing reusable widgets to consolidate

| Widget | Location | Status |
|---|---|---|
| `PrimaryButton` | `core/widgets/` | Good — already reusable |
| `InputFilled` | `core/widgets/` | Good — already reusable |
| `AppAvatar` | `core/widgets/` | Good — not exported in `ui.dart` barrel (fix) |
| `SectionDivider` | `core/widgets/` | Good |
| `SocialButton` | `core/widgets/` | Good |
| `BoomerangOverlay` | `core/widgets/` | Move to `features/feed/presentation/widgets/` (depends on feed) |
| Setting row pattern | Duplicated across settings pages | Extract `SettingTile` to `core/widgets/` |
| Stat display | `features/profile/presentation/widgets/stat.dart` | Consider promoting to core if used elsewhere |

---

## 7. State Management Rules (Riverpod)

### 7.1 Provider location

| Provider type | Where it lives |
|---|---|
| Firebase instance providers (`firebaseAuthProvider`, etc.) | `lib/infrastructure/providers.dart` |
| Feature repository providers | `features/<f>/application/<f>_providers.dart` (target) |
| Feature controllers | `features/<f>/application/` |
| UI-only state (`StateProvider`, `homeTabIndexProvider`) | `features/<f>/presentation/` co-located with the widget |

> **Current state:** All providers live in `infrastructure/providers.dart`. The target is to **migrate feature-specific providers** into their respective `application/` folders.

### 7.2 Provider types (when to use what)

| Use case | Provider type |
|---|---|
| Singleton service / repo | `Provider` |
| One-shot async data | `FutureProvider` |
| Real-time stream data | `StreamProvider` |
| Mutable UI-only state (e.g., tab index) | `StateProvider` |
| Complex mutable state with logic | `StateNotifierProvider` or `AsyncNotifierProvider` |
| Data keyed by parameter | `.family` modifier |

### 7.3 Naming conventions

```
<feature><Purpose>Provider          # e.g., authControllerProvider
<feature><Entity>RepoProvider       # e.g., boomerangRepoProvider
<feature><Data>StreamProvider       # e.g., notificationsStreamProvider
current<Entity>Provider             # e.g., currentUserProfileProvider
```

### 7.4 Controller rules

- Controllers **orchestrate**; they call domain repos, transform results, update state.
- Controllers must **not** import Firebase types — only domain interfaces and entities.
- Controllers must **not** perform UI navigation or show dialogs.
- The UI **reads** state and **dispatches** actions to controllers. It never mutates provider state directly.

**Reference model:** `AuthController` — receives `AuthRepo`, delegates every operation, maps errors.

---

## 8. Code Style & Naming Conventions

### 8.1 File naming

| Type | Convention | Example |
|---|---|---|
| Feature page | `<name>_page.dart` | `login_page.dart` |
| Widget | `<name>.dart` or `<name>_widget.dart` | `badge.dart`, `stat.dart` |
| Sheet / dialog | `<name>_sheet.dart` | `comments_sheet.dart` |
| Controller | `<feature>_controller.dart` | `auth_controller.dart` |
| Repository interface | `<feature>_repo.dart` | `auth_repo.dart` |
| Repository implementation | `firebase_<feature>_repo.dart` | `firebase_auth_repo.dart` |
| Entity / model | `<entity>.dart` | `auth_user.dart`, `user_profile.dart` |
| Provider file | `<feature>_providers.dart` | `auth_providers.dart` |

### 8.2 Class naming

| Type | Convention | Example |
|---|---|---|
| Page widget | `<Name>Page` | `LoginPage` |
| Reusable widget | `<Name>` or `<Name>Widget` | `PrimaryButton`, `AppAvatar` |
| Sheet | `<Name>Sheet` | `CommentsSheet` |
| Controller | `<Feature>Controller` | `AuthController` |
| Repo interface | `<Feature>Repo` | `AuthRepo` |
| Repo implementation | `Firebase<Feature>Repo` | `FirebaseAuthRepo` |
| Entity | `<Name>` | `AuthUser`, `UserProfile` |
| State class | `<Feature>State` | `AuthState` |
| Failure | `<Feature>Failure` | `AuthFailure` |

### 8.3 Import style

- Always use **package imports** (`package:boomerang/...`), never relative imports.
- Group imports: `dart:` → `package:flutter/` → `package:third_party/` → `package:boomerang/`.

### 8.4 Async handling

- Use `AsyncValue` from Riverpod for loading/error/data states in UI.
- Use `try/catch` in controllers; map exceptions to typed failures or user-facing strings.
- Never `await` inside `build()` — use `FutureProvider` or `FutureBuilder` instead.
- Use `.handleError()` on streams to prevent unhandled exceptions.

---

## 9. Design System Rules

### 9.1 Theme usage

The app has a centralised theme in `core/theme/app_theme.dart`. All UI code must reference it.

```dart
// GOOD
Theme.of(context).textTheme.titleLarge
Theme.of(context).colorScheme.primary
Theme.of(context).colorScheme.surface

// BAD
TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
Colors.black
Color(0xFFF4F4F4)
```

### 9.2 Rules

| Rule | Rationale |
|---|---|
| No hardcoded `Colors.*` in widgets | Use `Theme.of(context).colorScheme.*` or define semantic tokens |
| No inline `TextStyle(...)` constructors | Use `Theme.of(context).textTheme.*` and `.copyWith()` if needed |
| No magic color hex values (`Color(0xFF...)`) | Define them in theme or a `core/theme/app_colors.dart` constants file |
| Use `flutter_screenutil` consistently | All padding, margins, font sizes via `.w`, `.h`, `.sp`, `.r` |
| Define spacing constants | Create `core/theme/app_spacing.dart` for consistent spacing values |

### 9.3 Recommended theme extensions

Add to `core/theme/`:

```
core/theme/
├── app_theme.dart          # Existing — ThemeData builder
├── app_colors.dart         # Semantic color constants / extension on ColorScheme
└── app_spacing.dart        # Spacing tokens (xs, sm, md, lg, xl)
```

---

## 10. Anti-Patterns to Avoid

### 10.1 Critical (fix immediately)

| Anti-pattern | Where found | Fix |
|---|---|---|
| **Direct Firestore in widgets** | `comments_sheet.dart` uses `FirebaseFirestore.instance` | Route through `CommentsRepo` → provider |
| **God widgets (500+ lines)** | `home_tab.dart` (1059), `setup_flow_page.dart` (1057), `inbox_tab.dart` (628), `comments_sheet.dart` (593) | Decompose into smaller widgets + controllers |
| **Business logic in presentation** | Repo calls in `home_tab`, `discover_tab`, `inbox_tab`, `boomerang_editor_page`, `manage_account_page` | Move to controllers in application layer |
| **Core depends on features** | `core/widgets/boomerang_overlay.dart` imports `features/feed/` | Move to `features/feed/presentation/widgets/` |

### 10.2 High (fix in next sprint)

| Anti-pattern | Where found | Fix |
|---|---|---|
| **Missing domain layer** | `features/feed/` has no `domain/` | Add entities (Boomerang, Comment, Hashtag), repo interfaces |
| **No abstract repo interfaces** | `features/profile/infrastructure/`, `features/feed/infrastructure/` | Add abstract classes in domain; make infrastructure implement them |
| **Infra types leak into application** | `QueryDocumentSnapshot` used in `user_boomerangs_controller.dart` | Map to domain entities in the repo |
| **All providers in one file** | `infrastructure/providers.dart` (345 lines, all features) | Split into per-feature `application/<f>_providers.dart` files |
| **Hardcoded colors everywhere** | 20+ files use `Colors.*` and `Color(0xFF...)` | Replace with theme tokens |

### 10.3 Medium (address over time)

| Anti-pattern | Where found | Fix |
|---|---|---|
| **Cross-feature imports** | profile → feed, auth → profile, feed → profile | Decouple via core interfaces or navigation-only coupling |
| **Duplicated logic** | `LikesRepo` and `BoomerangRepo` both handle likes | Consolidate into single source of truth |
| **Side effects in build()** | FFmpeg callbacks in `app.dart` `build()` | Move to a one-time init provider |
| **`auth_error_mapper.dart` in core** | Core depends on `firebase_auth` | Move to `features/auth/infrastructure/` |
| **`firestore_paths.dart` in core** | Couples core to Firestore schema | Move to `core/utils/` but accept the trade-off, or move to infrastructure |
| **Incomplete barrel exports** | `ui.dart` doesn't export `avatar.dart` | Add missing exports |
| **`riverpod_generator` unused** | In `pubspec.yaml` dev_dependencies but not used | Either adopt code-gen or remove dependency |

---

## 11. Refactoring Guidelines

### Priority 1 — Establish missing layers

1. **Create `features/feed/domain/`**: Define `Boomerang`, `Comment`, `Hashtag` entities and abstract repository interfaces.
2. **Create `features/feed/application/`**: Move all feed business logic from presentation into controllers/providers.
3. **Add abstract repo interfaces** for profile and feed infrastructure classes.

### Priority 2 — Break up god widgets

Target the largest files first:

| File | Lines | Strategy |
|---|---|---|
| `setup_flow_page.dart` | 1057 | Split into step widgets: `NicknameStep`, `GenderStep`, `BirthdayStep`, `PhoneStep`, `AddressStep` |
| `home_tab.dart` | 1059 | Extract: `BoomerangFeedItem`, `FeedVideoPlayer`, `FeedActionBar`; move pagination to controller |
| `inbox_tab.dart` | 628 | Extract: `NotificationTile`, `FollowRequestTile`; move fetch/accept/reject to controller |
| `comments_sheet.dart` | 593 | Extract: `CommentTile`, `CommentInput`, `RepliesList`; route Firestore through repo |
| `discover_tab.dart` | 501 | Extract: `UserSearchResults`, `HashtagGrid`, `DiscoverBoomerangsGrid` |

### Priority 3 — Migrate providers

Move feature-specific providers from `infrastructure/providers.dart` into:

```
features/auth/application/auth_providers.dart
features/feed/application/feed_providers.dart
features/profile/application/profile_providers.dart
```

Keep only Firebase instance providers and cross-cutting utilities in `infrastructure/providers.dart`.

### Priority 4 — Design system cleanup

1. Create `core/theme/app_colors.dart` with semantic color constants.
2. Create `core/theme/app_spacing.dart` with spacing tokens.
3. Audit all widgets and replace hardcoded colors/styles with theme references.
4. Move `BoomerangOverlay` from `core/widgets/` to `features/feed/presentation/widgets/`.

### Priority 5 — Test coverage

Currently 3 test files. Expand:

1. **Domain logic** (pure functions — highest ROI): `follow_privacy`, `username_validation`, entity constructors.
2. **Controllers**: Mock repos, test state transitions.
3. **Repositories**: Mock Firestore, test mapping and error handling.

### Refactoring ground rules

- Refactor one layer at a time per feature; never rewrite everything at once.
- Keep the app compiling after every change — no "big bang" rewrites.
- Run `flutter analyze` after every refactoring pass.
- Write a test before extracting logic out of a widget (captures current behavior).
- Prefer moving code over rewriting it — preserve working logic.

---

## Appendix A — Reference Implementations

These existing files represent the **target quality** for each layer:

| Layer | Reference file | Why it's good |
|---|---|---|
| Domain entity | `features/auth/domain/auth_user.dart` | Freezed, immutable, pure Dart |
| Domain logic | `features/profile/domain/follow_privacy.dart` | Pure functions, testable, documented decisions |
| Domain model | `features/profile/domain/user_profile.dart` | Clean factory, no SDK dependencies |
| Repo interface | `features/auth/infrastructure/auth_repo.dart` | Minimal abstract contract |
| Repo implementation | `features/auth/infrastructure/firebase_auth_repo.dart` | Implements interface, wraps Firebase |
| Controller | `features/auth/application/auth_controller.dart` | Delegates to repo, maps errors, manages state |
| Shared widget | `core/widgets/primary_button.dart` | Small, reusable, single-purpose |
| Validation | `features/auth/domain/username_validation.dart` | Pure Dart, no dependencies |

## Appendix B — Tech Stack Summary

| Concern | Technology |
|---|---|
| Framework | Flutter (Material 3) |
| State management | Riverpod 2.x (manual providers) |
| Navigation | GoRouter |
| Backend | Firebase (Auth, Firestore, Storage, Messaging) |
| Immutability | Freezed + json_serializable |
| Responsive sizing | flutter_screenutil |
| Media processing | ffmpeg_kit_flutter_new, camera, video_player |
| Push notifications | firebase_messaging + flutter_local_notifications |
| Image handling | image_picker, image_cropper |
