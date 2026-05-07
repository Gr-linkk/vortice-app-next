import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/service_requests/service_request_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/service_request.dart';

class ClientServiceRequestListScreen extends ConsumerWidget {
  const ClientServiceRequestListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(clientServiceRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Service Requests')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clientServiceRequestsProvider),
        child: requestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorList(message: err.toString()),
          data: (requests) => requests.isEmpty
              ? const _EmptyList(
                  icon: Icons.support_agent_outlined,
                  title: 'No service requests yet',
                  message:
                      'Use Request Service when something needs attention.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: requests.length,
                  itemBuilder: (_, index) => _ServiceRequestCard(
                    request: requests[index],
                    clientMode: true,
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/client/service-requests/new'),
        icon: const Icon(Icons.add),
        label: const Text('Request Service'),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

class StaffServiceRequestListScreen extends ConsumerWidget {
  const StaffServiceRequestListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(staffServiceRequestsProvider);
    final role = ref.watch(profileProvider).valueOrNull?.role ?? UserRole.owner;
    final staffPrefix = role == UserRole.employee ? '/employee' : '/owner';

    return Scaffold(
      appBar: AppBar(title: const Text('Service Requests')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(staffServiceRequestsProvider);
          ref.invalidate(newServiceRequestCountProvider);
        },
        child: requestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorList(message: err.toString()),
          data: (requests) => requests.isEmpty
              ? const _EmptyList(
                  icon: Icons.inbox_outlined,
                  title: 'Inbox clear',
                  message: 'Client service requests will appear here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: requests.length,
                  itemBuilder: (_, index) => _ServiceRequestCard(
                    request: requests[index],
                    staffPrefix: staffPrefix,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ServiceRequestCard extends ConsumerWidget {
  const _ServiceRequestCard({
    required this.request,
    this.clientMode = false,
    this.staffPrefix,
  });

  final ServiceRequest request;
  final bool clientMode;
  final String? staffPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNew = request.status == ServiceRequestStatus.newRequest;
    final isUrgent = request.urgency == ServiceRequestUrgency.urgent;
    final color = request.status == ServiceRequestStatus.declined
        ? AppColors.error
        : request.status == ServiceRequestStatus.resolved
            ? AppColors.success
            : isUrgent
                ? AppColors.warning
                : AppColors.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.15),
                  child: Icon(
                    isUrgent ? Icons.priority_high : Icons.support_agent,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(
                  label: clientMode
                      ? request.clientStatusLabel
                      : request.staffStatusLabel,
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              request.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!clientMode && isNew) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _mark(
                        context,
                        ref,
                        ServiceRequestStatus.declined,
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _mark(
                        context,
                        ref,
                        ServiceRequestStatus.resolved,
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Handle'),
                    ),
                  ),
                ],
              ),
              if (request.assetId != null && staffPrefix != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    '$staffPrefix/work-orders/create?assetId=${request.assetId}',
                  ),
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Start Work Order'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String get _subtitle => [
        if (!clientMode && request.clientName != null) request.clientName,
        if (request.assetName != null) request.assetName,
        request.createdLabel,
        if (request.urgency == ServiceRequestUrgency.urgent) 'Urgent',
      ].join(' • ');

  Future<void> _mark(
    BuildContext context,
    WidgetRef ref,
    ServiceRequestStatus status,
  ) async {
    final success = await ref
        .read(serviceRequestControllerProvider.notifier)
        .updateStatus(request.id, status);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Request updated.' : 'Unable to update request.',
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 96),
        Icon(icon, color: AppColors.textSecondary, size: 48),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(message, style: const TextStyle(color: AppColors.error)),
      ],
    );
  }
}
