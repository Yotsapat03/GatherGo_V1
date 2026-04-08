# 🏃‍♂️ GatherGo V1 — Running Event Platform (Local Demo System)

## 📌 Overview

**GatherGo V1** is a full-stack running event platform that supports:

* User-created running sessions (**Spot Activities**)
* Admin-controlled events (**Big Events**)

This repository is configured for **local development and demo usage**, allowing the system to run without access to the original production database.

---

## 🎯 System Scope

The current implementation focuses on:

* Backend + database integration
* Local demo environment setup
* Core user and admin flows

This version is intended for **testing, demonstration, and reviewer validation**

---

## 🚀 Core Features (Implemented)

### 👤 User

* Register / Login
* Join Big Events
* Create / Join Spot Activities
* Chat in Spot rooms
* Basic activity participation tracking

---

### 🛠️ Admin

* Admin authentication
* Manage Big Events
* Access system data for monitoring

---

### ⚙️ System

* Role-based access (user / admin)
* Chat moderation (rule-based + optional AI support)
* Database-driven logic (PostgreSQL)
* Local demo data seeding

---

## 🏗️ Architecture (Actual Implementation)

* **Frontend:** Flutter
* **Backend:** Node.js (Express, CommonJS `.cjs`)
* **Database:** PostgreSQL

Flow:

* Flutter → API → Backend
* Backend → Database (PostgreSQL)

---

## 🗄️ Database

* Relational database (PostgreSQL)
* Uses:

  * Foreign key relationships
  * Structured tables for:

    * Users
    * Events (Big Event / Spot)
    * Chat & moderation
    * Payments (partial)

See:

* `DB_SETUP.md`
* `backend/migrations/`

---

## 🧱 Tech Stack

### Backend

* Node.js
* Express
* PostgreSQL

### Frontend

* Flutter (Dart)

---

## 📁 Project Structure

```
gathergo/      → Flutter application
backend/       → API + database logic
backend/migrations/ → SQL migrations
backend/scripts/    → setup scripts
```

---

## ⚙️ Backend Setup

```bash
cd backend
npm install
```

### Create environment file

Windows:

```powershell
Copy-Item .env.example .env
```

macOS/Linux:

```bash
cp .env.example .env
```

---

## 🔑 Required Environment Variables

```env
DATABASE_URL= postgresql://postgres:Ee125403@localhost:5432/run_event_db2
PORT= 3000
```

If `DATABASE_URL` is missing, the backend will not start.

---

## 🧩 Optional Configuration

These enable additional features but are **not required for demo**:

* OPENAI_API_KEY → AI moderation support
* GOOGLE_MAPS_API_KEY → map-related features
* STRIPE_* → Stripe payment flow (partial support)
---

## 🗃️ Database Setup

```bash
npm run db:migrate
npm run db:preflight
npm run db:seed-demo
```

Or:

```bash
npm run setup:demo
```

---

## ▶️ Start Backend

```bash
npm start
```

Default:

```
http://localhost:3000
```

---

## 📱 Flutter Setup

```bash
cd gathergo
flutter pub get
```

Run:

```bash
flutter run --dart-define API_URL=http://localhost:3000
```

---

## 🔑 Demo Accounts

After seeding:

### 👤 Users

* [a@b.com](mailto:a@b.com) / 12345678
* [b@c.com](mailto:b@c.com) / 12345678
* [c@d.com](mailto:c@d.com) / 12345678

### 🛠️ Admin

* [admin@test.com](mailto:admin@test.com) / MyPassword123

---

## ⚠️ Current Limitations

* Payment integrations are **partially implemented / require external setup**
* AI moderation depends on API configuration
* Some flows are designed for demo, not full production usage

---

## 🧪 Recommended Demo Scope

* Login (user / admin)
* Big Event participation
* Spot activities
* Chat moderation behavior

---

## ⚡ Quick Start (Reviewer)

```bash
cd backend
npm install
npm run setup:demo
npm start
```

Then:

```bash
cd gathergo
flutter run --dart-define API_URL=http://localhost:3000
```

---

## 🚫 Important Notes

* Do NOT commit `backend/.env`
* Do NOT commit `backend/uploads`
* Do NOT use real production data

---

## 📌 Notes

This project demonstrates a **working backend + database system** with a Flutter frontend, suitable for:

* Local demo
* System testing
* Academic evaluation

---
