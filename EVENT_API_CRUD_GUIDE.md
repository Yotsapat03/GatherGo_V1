# Event API CRUD Methods - Developer Guide

## Overview
The `EventApi` class now provides complete CRUD operations for events with proper error handling and timeouts.

## Available Methods

### 1. CREATE - `createEvent()`
**Purpose:** Create a new big event

**Signature:**
```dart
Future<Map<String, dynamic>> createEvent({
  required int organizationId,
  required String description,
  required String meetingPoint,
  required DateTime startAt,
  String? title,
  int? maxParticipants,
  int createdBy = 1,
  double? fee,
  String visibility = "public",
  String status = "published",
  String type = "BIG_EVENT",
}) async
```

**Example Usage:**
```dart
try {
  final result = await EventApi.instance.createEvent(
    organizationId: 1,
    title: "Tech Conference 2024",
    description: "Annual tech conference for developers",
    meetingPoint: "Central Plaza",
    startAt: DateTime(2024, 12, 25, 10, 0),
    maxParticipants: 500,
    fee: 1000.0,
    visibility: "public",
    status: "published",
  );
  
  print("Event created: ${result['id']}");
  print("Event URL: ${result['cover_url']}");
} on Exception catch (e) {
  print("Creation failed: $e");
  // Handle error - could be network or format issue
}
```

**Returns:** Event object with generated ID and URLs

---

### 2. READ - `getEventDetail()` ⭐ NEW
**Purpose:** Retrieve details of a specific event

**Signature:**
```dart
Future<Map<String, dynamic>> getEventDetail(int eventId) async
```

**Example Usage:**
```dart
try {
  final event = await EventApi.instance.getEventDetail(123);
  
  final title = event['title'] ?? 'Untitled';
  final startAt = event['start_at'] ?? '';
  final maxParticipants = event['max_participants'] ?? 0;
  
  print("Event: $title");
  print("Start: $startAt");
  print("Max: $maxParticipants");
} on Exception catch (e) {
  print("Failed to load event: $e");
}
```

**Returns:** Single event object with all details

**Status Codes:**
- 200: Success
- 404: Event not found
- 500: Server error

---

### 3. READ - `listEventsByOrg()`
**Purpose:** List all events for a specific organization

**Signature:**
```dart
Future<List<dynamic>> listEventsByOrg(int orgId) async
```

**Example Usage:**
```dart
try {
  final events = await EventApi.instance.listEventsByOrg(1);
  
  for (final event in events) {
    print("${event['title']} - ${event['start_at']}");
  }
} on Exception catch (e) {
  print("Failed to list events: $e");
}
```

**Returns:** List of event objects

---

### 4. UPDATE - `updateEvent()` ⭐ NEW
**Purpose:** Update an existing event

**Signature:**
```dart
Future<Map<String, dynamic>> updateEvent(
  int eventId,
  Map<String, dynamic> data,
) async
```

**Example Usage:**
```dart
try {
  final updated = await EventApi.instance.updateEvent(
    123,  // Event ID
    {
      'title': 'Updated Tech Conference 2024',
      'max_participants': 600,
      'status': 'published',
      'fee': 1200.0,
    },
  );
  
  print("Event updated successfully");
  print("New title: ${updated['title']}");
} on Exception catch (e) {
  print("Update failed: $e");
}
```

**Supported Fields:**
- `title` - Event title
- `description` - Event description
- `meeting_point` - Meeting location
- `start_at` - Start date/time (ISO8601 format)
- `max_participants` - Maximum attendees
- `fee` - Entry fee (optional)
- `status` - "draft" | "published" | "closed" | "cancelled"
- `visibility` - "public" | "private"
- `type` - Event type

**Returns:** Updated event object

**Status Codes:**
- 200: Success
- 400: Invalid data
- 404: Event not found
- 500: Server error

---

### 5. DELETE - `deleteEvent()` ⭐ NEW
**Purpose:** Delete an event

**Signature:**
```dart
Future<void> deleteEvent(int eventId) async
```

**Example Usage:**
```dart
try {
  await EventApi.instance.deleteEvent(123);
  print("Event deleted successfully");
} on Exception catch (e) {
  print("Deletion failed: $e");
}
```

**Returns:** Nothing (void)

**Status Codes:**
- 200/204: Success
- 404: Event not found
- 500: Server error

---

## Error Handling

All methods use unified exception handling with automatic timeouts:

```dart
try {
  final result = await EventApi.instance.getEventDetail(123);
  // Process result
} on Exception catch (e) {
  // Single catch handles:
  // - Network timeouts (20 second limit)
  // - Network connection errors
  // - Invalid JSON responses
  // - HTTP error status codes
  
  print("Error: $e");
  // Error message format: "Network/Format error: <details>"
}
```

### Timeout Behavior
- All requests have a **20-second timeout**
- If the server doesn't respond in 20 seconds, the request fails with a timeout exception
- This prevents the UI from freezing indefinitely

### Example Error Messages
```
Network/Format error: 404 Not Found
Network/Format error: Connection reset by peer
Network/Format error: Invalid response JSON (expected object)
Network/Format error: Read timed out
```

---

## Best Practices

### 1. Always Use Try-Catch
```dart
// ✅ Good
try {
  final event = await EventApi.instance.getEventDetail(id);
} on Exception catch (e) {
  // Handle error
}

// ❌ Avoid
final event = await EventApi.instance.getEventDetail(id);  // No error handling!
```

### 2. Check Data Validity
```dart
// ✅ Good
final title = event['title'] ?? 'Untitled';
final fee = (event['fee'] ?? 0).toDouble();

// ❌ Avoid
final title = event['title'];  // Could be null!
final fee = event['fee'].toDouble();  // Could crash!
```

### 3. Use Consistent DateTime Format
```dart
// ✅ Good - Use DateTime.now() or parse ISO8601
final now = DateTime.now();
final isoString = now.toIso8601String();

// When reading from API:
final startAt = DateTime.tryParse(event['start_at'] ?? '') ?? DateTime.now();

// ❌ Avoid - Don't mix date formats
final startAt = '2024-12-25 10:00';  // Inconsistent!
```

### 4. Show User Feedback
```dart
try {
  setState(() => _loading = true);
  
  final event = await EventApi.instance.getEventDetail(id);
  
  setState(() {
    _event = event;
    _loading = false;
  });
} on Exception catch (e) {
  setState(() {
    _error = "Failed to load event: $e";
    _loading = false;
  });
  
  // Show snackbar, alert, or error UI
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("Error: $_error")),
  );
}
```

---

## Integration Examples

### In a StatefulWidget
```dart
class EventDetailPage extends StatefulWidget {
  final int eventId;

  const EventDetailPage({required this.eventId});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Future<Map<String, dynamic>> _eventFuture;

  @override
  void initState() {
    super.initState();
    _eventFuture = EventApi.instance.getEventDetail(widget.eventId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _eventFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        final event = snapshot.data!;
        return ListView(
          children: [
            Text(event['title'] ?? ''),
            Text(event['description'] ?? ''),
            // ... more widgets
          ],
        );
      },
    );
  }
}
```

### In a ViewModel/Provider
```dart
class EventViewModel extends ChangeNotifier {
  Map<String, dynamic>? _event;
  bool _loading = false;
  String? _error;

  Future<void> loadEvent(int eventId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _event = await EventApi.instance.getEventDetail(eventId);
    } on Exception catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateEvent(int eventId, Map<String, dynamic> data) async {
    try {
      _event = await EventApi.instance.updateEvent(eventId, data);
    } on Exception catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  get event => _event;
  get loading => _loading;
  get error => _error;
}
```

---

## Testing

### Unit Test Example
```dart
test('getEventDetail returns event when successful', () async {
  final api = EventApi.instance;
  // Mock or use test server
  
  final event = await api.getEventDetail(1);
  
  expect(event, isNotNull);
  expect(event['id'], equals(1));
  expect(event['title'], isNotEmpty);
});

test('getEventDetail throws on timeout', () async {
  final api = EventApi.instance;
  // Use slow/unresponsive server
  
  expect(
    () => api.getEventDetail(999),
    throwsException,
  );
});
```

---

## API Endpoints Reference

| Method | Endpoint | Status Codes |
|--------|----------|-------------|
| CREATE | `POST /api/events` | 201, 400, 500 |
| READ   | `GET /api/events/{id}` | 200, 404, 500 |
| READ   | `GET /api/organizations/{orgId}/events` | 200, 400, 500 |
| UPDATE | `PUT /api/events/{id}` | 200, 400, 404, 500 |
| DELETE | `DELETE /api/events/{id}` | 200, 204, 404, 500 |

---

## Summary

| Method | Purpose | New | Status |
|--------|---------|-----|--------|
| `createEvent()` | Create event | No | ✅ Updated |
| `getEventDetail()` | Get single event | **Yes** | ✅ Ready |
| `listEventsByOrg()` | Get org events | No | ✅ Updated |
| `updateEvent()` | Update event | **Yes** | ✅ Ready |
| `deleteEvent()` | Delete event | **Yes** | ✅ Ready |

All methods are production-ready with proper error handling and timeouts.
