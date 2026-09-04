import 'package:flutter/material.dart';

/// Standalone mockup — run with:
///   flutter run -t lib/mockups/hire_reject_mockup.dart
///
/// Demonstrates the proposed animated hire / reject / undo UX
/// without touching any production code.
void main() => runApp(const MaterialApp(home: _MockupScaffold()));

class _MockupScaffold extends StatelessWidget {
  const _MockupScaffold();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HRMDO — Hire / Reject Mockup',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                Expanded(child: _BrowseMockup()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Browse mockup with animated rows
// ──────────────────────────────────────────────────────────────────────────────

class _Applicant {
  _Applicant(this.name, this.municipality, this.status);
  final String name;
  final String municipality;
  String status;
}

class _BrowseMockup extends StatefulWidget {
  @override
  State<_BrowseMockup> createState() => _BrowseMockupState();
}

class _BrowseMockupState extends State<_BrowseMockup>
    with SingleTickerProviderStateMixin {
  final _applicants = [
    _Applicant('Maria Santos', 'Maramag', 'On Process'),
    _Applicant('Juan Dela Cruz', 'Kitaotao', 'On Process'),
    _Applicant('Ana Reyes', 'Quezon', 'Recommended'),
    _Applicant('Pedro Mendoza', 'Damulog', 'Interview Set'),
    _Applicant('Rosa Garcia', 'Maramag', 'On Process'),
    _Applicant('Luis Bautista', 'Kibawe', 'On Process'),
  ];

  // Track which rows are currently animating out
  final Set<int> _exitingRows = {};
  // Track which rows just had a status change (for flash effect)
  final Set<int> _flashingRows = {};

  // Undo state
  String? _undoMessage;
  _VoidCallback? _onUndo;
  Timer? _undoTimer;

  late final AnimationController _tabPulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final Animation<double> _tabPulse =
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 1),
      ]).animate(CurvedAnimation(parent: _tabPulseCtrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _undoTimer?.cancel();
    _tabPulseCtrl.dispose();
    super.dispose();
  }

  void _showUndo(String message, _VoidCallback undoAction) {
    _undoTimer?.cancel();
    setState(() {
      _undoMessage = message;
      _onUndo = undoAction;
    });
    _undoTimer = Timer(const Duration(seconds: 8), () {
      setState(() {
        _undoMessage = null;
        _onUndo = null;
      });
    });
  }

  void _hire(int index) {
    final a = _applicants[index];
    showDialog(
      context: context,
      builder: (ctx) => _HireDialog(
        name: a.name,
        onConfirm: (position) {
          Navigator.of(ctx).pop();
          // Animate row exit
          setState(() => _exitingRows.add(index));
          _tabPulseCtrl.forward(from: 0);
          Future.delayed(const Duration(milliseconds: 350), () {
            if (!mounted) return;
            setState(() {
              _exitingRows.remove(index);
              _applicants.removeAt(index);
            });
          });
          _showUndo('${a.name} hired as $position', () {
            setState(() => _applicants.insert(index, a));
          });
        },
      ),
    );
  }

  void _reject(int index) {
    final a = _applicants[index];
    showDialog(
      context: context,
      builder: (ctx) => _RejectDialog(
        name: a.name,
        onConfirm: () {
          Navigator.of(ctx).pop();
          // Flash + status change
          setState(() {
            a.status = 'Rejected';
            _flashingRows.add(index);
          });
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            setState(() => _flashingRows.remove(index));
          });
          _showUndo('${a.name} rejected', () {
            setState(() => a.status = 'On Process');
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Tabs ──
        _Tabs(
          listCount: _applicants.where((a) => a.status != 'Hired').length,
          hiredCount: _applicants.where((a) => a.status == 'Hired').length,
          pulseAnimation: _tabPulse,
        ),
        const SizedBox(height: 16),
        // ── Column headers ──
        _HeaderRow(),
        const SizedBox(height: 4),
        // ── Rows ──
        Expanded(
          child: ListView.builder(
            itemCount: _applicants.length,
            itemBuilder: (context, i) {
              final a = _applicants[i];
              final isExiting = _exitingRows.contains(i);
              final isFlashing = _flashingRows.contains(i);
              final isRejected = a.status == 'Rejected';
              return _AnimatedRow(
                key: ValueKey(a.name),
                isExiting: isExiting,
                isFlashing: isFlashing,
                isRejected: isRejected,
                index: i,
                child: _RowTile(
                  applicant: a,
                  onHire: () => _hire(i),
                  onReject: () => _reject(i),
                ),
              );
            },
          ),
        ),
        // ── Undo banner ──
        if (_undoMessage != null)
          _UndoBanner(
            message: _undoMessage!,
            onUndo: () {
              _onUndo?.call();
              _undoTimer?.cancel();
              setState(() {
                _undoMessage = null;
                _onUndo = null;
              });
            },
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Animated row wrapper
// ──────────────────────────────────────────────────────────────────────────────

class _AnimatedRow extends StatefulWidget {
  const _AnimatedRow({
    super.key,
    required this.child,
    required this.isExiting,
    required this.isFlashing,
    required this.isRejected,
    required this.index,
  });
  final Widget child;
  final bool isExiting;
  final bool isFlashing;
  final bool isRejected;
  final int index;

  @override
  State<_AnimatedRow> createState() => _AnimatedRowState();
}

class _AnimatedRowState extends State<_AnimatedRow> {
  @override
  Widget build(BuildContext context) {
    Color bgColor;
    if (widget.isFlashing) {
      bgColor = const Color(0x22FF5252); // red flash
    } else if (widget.isRejected) {
      bgColor = const Color(0x0AFF5252); // very subtle red tint
    } else {
      bgColor = widget.index.isOdd
          ? const Color(0xFFFFFFFF)
          : const Color(0xFFFAFBFD);
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: widget.isExiting ? 0.0 : 1.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        offset: widget.isExiting ? const Offset(-0.3, 0) : Offset.zero,
        curve: Curves.easeInCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: bgColor,
          child: widget.child,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tabs
// ──────────────────────────────────────────────────────────────────────────────

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.listCount,
    required this.hiredCount,
    required this.pulseAnimation,
  });
  final int listCount;
  final int hiredCount;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Tab(label: 'List of Applicants', count: listCount, active: true),
        const SizedBox(width: 8),
        ScaleTransition(
          scale: pulseAnimation,
          child: _Tab(label: 'Hired Applicants', count: hiredCount, active: false),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.active,
  });
  final String label;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFFF0F1F5),
        borderRadius: BorderRadius.circular(8),
        border: active
            ? Border.all(color: const Color(0xFF2D3748), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? const Color(0xFF2D3748) : const Color(0xFF718096))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2D3748) : const Color(0xFFCBD5E0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : const Color(0xFF4A5568))),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Header row
// ──────────────────────────────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        children: [
          SizedBox(width: 32), // checkbox
          Expanded(flex: 3, child: _HeaderCell('APPLICANT')),
          Expanded(flex: 2, child: _HeaderCell('MUNICIPALITY')),
          Expanded(flex: 2, child: _HeaderCell('STATUS')),
          Expanded(flex: 2, child: _HeaderCell('ACTION')),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF718096),
            letterSpacing: 0.5));
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Row tile
// ──────────────────────────────────────────────────────────────────────────────

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.applicant,
    required this.onHire,
    required this.onReject,
  });
  final _Applicant applicant;
  final VoidCallback onHire;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final isRejected = applicant.status == 'Rejected';
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Checkbox(
              value: false,
              onChanged: (_) {},
              visualDensity: VisualDensity.compact,
            ),
          ),
          // Avatar + name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFFEDF2F7),
                  child: Text(
                    applicant.name[0],
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(applicant.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          // Municipality
          Expanded(
            flex: 2,
            child: Text(applicant.municipality,
                style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568))),
          ),
          // Status pill
          Expanded(
            flex: 2,
            child: _StatusPill(status: applicant.status),
          ),
          // Actions
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _ActionBtn(
                  label: 'Hire',
                  color: const Color(0xFF38A169),
                  onPressed: isRejected ? null : onHire,
                ),
                const SizedBox(width: 6),
                _ActionBtn(
                  label: 'Reject',
                  color: const Color(0xFFE53E3E),
                  onPressed: isRejected ? null : onReject,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Rejected' => (const Color(0xFFFED7D7), const Color(0xFFC53030)),
      'Recommended' => (const Color(0xFFC6F6D5), const Color(0xFF276749)),
      'Interview Set' => (const Color(0xFFFEFCBF), const Color(0xFF975A16)),
      _ => (const Color(0xFFFEFCBF), const Color(0xFF975A16)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onPressed,
  });
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: disabled ? const Color(0xFFE2E8F0) : color),
        foregroundColor: disabled ? const Color(0xFFA0AEC0) : color,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Hire dialog (mockup)
// ──────────────────────────────────────────────────────────────────────────────

class _HireDialog extends StatefulWidget {
  const _HireDialog({required this.name, required this.onConfirm});
  final String name;
  final ValueChanged<String> onConfirm;

  @override
  State<_HireDialog> createState() => _HireDialogState();
}

class _HireDialogState extends State<_HireDialog> {
  final _positionCtrl = TextEditingController();
  DateTime? _dateHired;

  @override
  void dispose() {
    _positionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFC6F6D5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle_outline,
                color: Color(0xFF38A169), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Hire ${widget.name}')),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini applicant card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFEDF2F7),
                    child: Icon(Icons.person, size: 18, color: Color(0xFFA0AEC0)),
                  ),
                  const SizedBox(width: 10),
                  Text(widget.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Position field
            TextField(
              controller: _positionCtrl,
              decoration: InputDecoration(
                labelText: 'Final Position',
                hintText: 'e.g. Admin Aide III',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            // Date picker button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_dateHired == null
                    ? 'Pick date hired'
                    : '${_dateHired!.month}/${_dateHired!.day}/${_dateHired!.year}'),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2005),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _dateHired = d);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF38A169),
          ),
          onPressed: _positionCtrl.text.trim().isEmpty || _dateHired == null
              ? null
              : () => widget.onConfirm(_positionCtrl.text.trim()),
          child: const Text('Hire'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Reject dialog (mockup)
// ──────────────────────────────────────────────────────────────────────────────

class _RejectDialog extends StatelessWidget {
  const _RejectDialog({required this.name, required this.onConfirm});
  final String name;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFED7D7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.cancel_outlined,
                color: Color(0xFFE53E3E), size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Reject Application'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Applicant card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFFED7D7),
                    child: Icon(Icons.person, size: 18, color: Color(0xFFE53E3E)),
                  ),
                  const SizedBox(width: 10),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This applicant will be marked as Rejected and removed from the active list.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE53E3E),
          ),
          onPressed: onConfirm,
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Undo banner
// ──────────────────────────────────────────────────────────────────────────────

class _UndoBanner extends StatelessWidget {
  const _UndoBanner({required this.message, required this.onUndo});
  final String message;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2D3748),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                style: const TextStyle(
                    fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onUndo,
              child: Text('UNDO',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber[300])),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Timer helper (minimal, just for undo timeout)
// ──────────────────────────────────────────────────────────────────────────────

class Timer {
  factory Timer(Duration duration, VoidCallback onTick) {
    _active?.cancel();
    // Simplified: just call onTick after duration
    Future.delayed(duration, onTick);
    return Timer._(duration, onTick);
  }

  Timer._(this.duration, this.onTick);

  static Timer? _active;

  final Duration duration;
  final VoidCallback onTick;

  void cancel() {}
}

typedef _VoidCallback = VoidCallback;
