# 🏃‍♂️ GatherGo V1 — Running Event Platform (Production-Ready Demo)

## 📌 Overview

**GatherGo V1** is a full-stack running event platform designed to connect runners through social activities and structured events.
The system supports both **user-generated running sessions (Spot Activities)** and **official events (Big Events)** managed by administrators.

This repository is prepared for **local demo setup**, allowing reviewers to clone and run the system without access to the original developer database.

---

## 🎯 Project Purpose

GatherGo is designed to:

* Connect runners through **community-based activities**
* Provide structured participation via **official running events**
* Enhance safety using **AI-assisted chat moderation**
* Support event organization through an **admin management system**

The system integrates social interaction, event participation, and moderation into a unified platform.

---

## 🚀 Core Features

### 👤 User Features

* User registration and authentication
* Join **Big Events**
* Create and join **Spot Activities**
* Real-time chat with moderation system
* Track participation and running distance

### 🛠️ Admin Features

* Manage Big Events
* Monitor user activity
* Review reports and moderation logs
* Control system-level data

### ⚙️ System Features

* Role-Based Access Control (RBAC)
* AI-assisted chat moderation (optional)
* QR-based payment integration (optional)
* Relational database with constraints (PostgreSQL)

---

## 🏗️ System Architecture

* **Frontend:** Flutter (Mobile / Web)
* **Backend:** Node.js (Express, CommonJS)
* **Database:** PostgreSQL (Relational Database)

The system follows a **client-server architecture**:

* Flutter communicates with backend APIs
* Backend handles business logic and validation
* PostgreSQL stores structured relational data

---

## 🗄️ Database Design

* Designed using **Relational Model (3NF)**
* Enforced **Foreign Key Constraints**
* Structured modules include:

  * Users & Roles
  * Big Events & Spots
  * Chat & Moderation
  * Payments & Receipts

For full schema details, see:

* `DB_SETUP.md`
* `backend/.env.example`

---

## 🧱 Tech Stack (Actual Implementation)

### Backend

* Node.js (CommonJS - `.cjs`)
* Express.js
* PostgreSQL

### Frontend

* Flutter (Dart)

### Optional Integrations

* OpenAI (AI moderation)
* Stripe (payments)
* Google Maps API

---

## 📁 Repository Structure

```
gathergo/      → Flutter application
backend/       → Node.js + PostgreSQL backend
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

**Windows**

```powershell
Copy-Item .env.example .env
```

**macOS/Linux**

```bash
cp .env.example .env
```

---

### 🔑 Required Environment Variables

```env
DATABASE_URL=
PORT=
```

The backend will fail to start if `DATABASE_URL` is missing.

---

### 🧩 Optional Variables

* `OPENAI_API_KEY`
* `GOOGLE_MAPS_API_KEY`
* `STRIPE_*`
* `AIRWALLEX_*`
* `ANTOM_*`

These enable advanced features but are **not required for demo**.

---

## 🗃️ Database Setup

```bash
npm run db:migrate
npm run db:preflight
npm run db:seed-demo
```

Or run everything in one step:

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

### Run (Web/Desktop)

```bash
flutter run --dart-define API_URL=http://localhost:3000
```

### Android Emulator

```bash
flutter run --dart-define API_URL=http://10.0.2.2:3000
```

### Physical Device

```bash
flutter run --dart-define API_URL=http://YOUR_LOCAL_IP:3000
```

---

🔑 Demo Accounts

You can use the following accounts after running npm run db:seed-demo:

👤 Users
User 1
Email: a@b.com
Password: 12345678

User 2
Email: b@c.com
Password: 12345678

User 3
Email: c@d.com
Password: 12345678
🛠️ Admin
Email: admin@test.com
Password: MyPassword123

⚠️ Note:

These are demo accounts for testing purposes only
Data can be reset anytime using the seed script

---

## ⚠️ Limitations

* Some payment integrations require external provider approval
* AI moderation requires API keys
* Certain production edge cases are not fully covered in demo mode

---

## ✅ Production-Ready Aspects

* Structured backend architecture
* Database migrations and seed system
* Environment-based configuration
* Error handling and validation
* Clear separation between user and admin systems

---

## 🧪 Recommended Demo Scope

For reviewers:

* User login
* Admin login
* Big Event participation
* Spot activities
* Chat moderation

---

## ⚡ Reviewer Quick Start

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
* Do NOT upload real production data

---

## 📌 Final Note

This project focuses on demonstrating a **real working system with backend + database integration**, suitable for academic evaluation, demo presentation, and system validation.

---
