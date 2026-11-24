import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../domain/models.dart';
import '../../app/app_state.dart';
import '../network/api_client.dart';

void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    ) ??
    false;

class PageBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const PageBody({super.key, required this.children, this.maxWidth = 960});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width >= 700 ? 32 : 20,
        vertical: 16,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionTitle(this.title, {super.key, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, body;
  final IconData icon;
  const EmptyState(
    this.title,
    this.body, {
    super.key,
    this.icon = Icons.inventory_2_outlined,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color =
        ['cancelled', 'deleted', 'not_selected'].contains(status)
            ? theme.colorScheme.error
            : ['delivered', 'accepted'].contains(status)
            ? (dark ? const Color(0xff81D8AA) : const Color(0xff167044))
            : ['draft', 'pending', 'ready'].contains(status)
            ? (dark ? const Color(0xffF3C76D) : const Color(0xff875D05))
            : theme.colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 7, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                statusLabel(status),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? action;
  const TaskButton(this.label, {super.key, this.icon, this.action});
  @override
  State<TaskButton> createState() => _TaskButtonState();
}

class _TaskButtonState extends State<TaskButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed:
        busy || widget.action == null
            ? null
            : () async {
              setState(() => busy = true);
              try {
                await widget.action!();
              } catch (e) {
                if (context.mounted) message(context, e.toString());
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
    icon:
        busy
            ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            : Icon(widget.icon ?? Icons.arrow_forward_rounded),
    label: Text(busy ? 'Procesando…' : widget.label),
  );
}

class DataView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(T) builder;
  final int revision;
  const DataView({
    super.key,
    required this.load,
    required this.builder,
    this.revision = 0,
  });
  @override
  State<DataView<T>> createState() => _DataViewState<T>();
}

class _DataViewState<T> extends State<DataView<T>> {
  late Future<T> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  @override
  void didUpdateWidget(covariant DataView<T> old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (c, s) {
      if (s.connectionState != ConnectionState.done) {
        if (s.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LinearProgressIndicator(minHeight: 2),
              widget.builder(s.data as T),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
              Text(
                'Consultando tus encargos…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
      }
      if (s.hasError) {
        return Column(
          children: [
            EmptyState(
              'No se pudo cargar',
              s.error is ApiFailure
                  ? s.error.toString()
                  : 'No se pudo consultar esta información. Tu sesión y tus borradores no se borraron.',
              icon: Icons.cloud_off_outlined,
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() => future = widget.load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        );
      }
      return widget.builder(s.data as T);
    },
  );
}

class PhotoView extends StatefulWidget {
  final Photo photo;
  final double height;
  final bool zoom;
  const PhotoView(this.photo, {super.key, this.height = 180, this.zoom = true});
  @override
  State<PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends State<PhotoView> {
  Future<String>? url;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url();
  }

  @override
  void didUpdateWidget(covariant PhotoView old) {
    super.didUpdateWidget(old);
    if (old.photo.objectPath != widget.photo.objectPath) {
      url = null;
      _url();
    }
  }

  void _url() {
    if (widget.photo.objectPath != null) {
      url ??= context.read<AppState>().repository!.imageUrl(widget.photo);
    }
  }

  Widget image() {
    final p = widget.photo;
    final error = Container(
      height: widget.height,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: const Center(child: Icon(Icons.broken_image_outlined, size: 32)),
    );
    if (p.localPath != null && File(p.localPath!).existsSync()) {
      return Image.file(
        File(p.localPath!),
        height: widget.height,
        width: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: widget.zoom ? 500 : 1600,
        errorBuilder: (_, _, _) => error,
      );
    }
    if (url != null) {
      return FutureBuilder<String>(
        future: url,
        builder:
            (c, s) =>
                s.hasData
                    ? Image.network(
                      s.data!,
                      height: widget.height,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      cacheWidth: widget.zoom ? 500 : 1600,
                      errorBuilder: (_, _, _) => error,
                    )
                    : s.hasError
                    ? error
                    : SizedBox(
                      height: widget.height,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
      );
    }
    return error;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Foto de referencia',
    button: widget.zoom,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap:
            widget.zoom
                ? () => openPage(
                  context,
                  Scaffold(
                    appBar: AppBar(title: const Text('Foto de referencia')),
                    body: Center(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: PhotoView(
                          widget.photo,
                          height: MediaQuery.sizeOf(context).height * .7,
                          zoom: false,
                        ),
                      ),
                    ),
                  ),
                )
                : null,
        child: image(),
      ),
    ),
  );
}

class RequestCard extends StatelessWidget {
  final RequestItem request;
  final VoidCallback onTap;
  const RequestCard(this.request, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (request.photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PhotoView(request.photos.first, height: 150),
                ),
              if (request.photos.isEmpty)
                Container(
                  height: 100,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 30,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Una idea por crear',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              Text(
                request.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text('${request.quantity} unidades · ${request.district}'),
              Text('Para el ${dateOnly(request.desiredDate)}'),
              if (!context.read<AppState>().isBusiness)
                Text('${request.quoteCount} cotizaciones recibidas'),
              StatusChip(request.status),
            ],
          ),
        ),
      ),
    ),
  );
}
