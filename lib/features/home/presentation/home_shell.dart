import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/app_state.dart';
import '../../../core/widgets/common.dart';
import '../../marketplace/presentation/market_screens.dart';
import '../../profile/presentation/account_screens.dart';
import '../domain/home_overview.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  String? selectedCategory;
  final visited = <int>{0};
  void select(int index) => setState(() {
    tab = index;
    visited.add(index);
  });
  void explore([String? category]) => setState(() {
    selectedCategory = category;
    tab = 1;
    visited.add(1);
  });
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final business = app.isBusiness;
    final pages = <Widget>[
      _Dashboard(
        onExplore: () => explore(),
        onCategory: explore,
        onOrders: () => select(business ? 3 : 2),
      ),
      RequestListScreen(
        key: ValueKey(selectedCategory),
        business: business,
        initialCategory: selectedCategory,
      ),
      if (business) const BusinessQuotesScreen(),
      const OrdersScreen(),
      const ProfileScreen(),
    ];
    final titles =
        business
            ? [
              'Encárgalo',
              'Explorar',
              'Mis cotizaciones',
              'Pedidos',
              'Mi negocio',
            ]
            : ['Encárgalo', 'Mis solicitudes', 'Mis pedidos', 'Mi perfil'];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              business ? Icons.storefront_rounded : Icons.local_mall_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Text(titles[tab]),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronización',
            onPressed: () => openPage(context, const SyncScreen()),
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () => openPage(context, const NotificationsScreen()),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Build a destination only after its first visit, then retain its state.
      // This avoids eager network requests and losing form/list positions.
      body: IndexedStack(
        index: tab,
        children: [
          for (var i = 0; i < pages.length; i++)
            visited.contains(i) ? pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: select,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(
              business
                  ? Icons.travel_explore_outlined
                  : Icons.description_outlined,
            ),
            label: business ? 'Explorar' : 'Solicitudes',
          ),
          if (business)
            const NavigationDestination(
              icon: Icon(Icons.request_quote_outlined),
              label: 'Cotizaciones',
            ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Pedidos',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            label: business ? 'Negocio' : 'Perfil',
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final VoidCallback onExplore, onOrders;
  final ValueChanged<String> onCategory;
  const _Dashboard({
    required this.onExplore,
    required this.onOrders,
    required this.onCategory,
  });
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.profile!;
    final scheme = Theme.of(context).colorScheme;
    return PageBody(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: scheme.onPrimary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CREADO EN PIURA',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Hola, ${p.name.split(' ').first}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: .8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.isBusiness
                    ? 'Tu talento.\nSu próxima idea.'
                    : 'Tú lo imaginas.\nAquí lo encargas.',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                p.isBusiness
                    ? 'Encuentra oportunidades de tus categorías y construye acuerdos claros.'
                    : 'Encuentra negocios locales para tus productos personalizados.',
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: .9),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.primary,
                ),
                onPressed:
                    p.isBusiness ? onExplore : () => createRequest(context),
                icon: Icon(
                  p.isBusiness ? Icons.search_rounded : Icons.add_rounded,
                ),
                label: Text(
                  p.isBusiness ? 'Ver oportunidades' : 'Crear mi solicitud',
                ),
              ),
            ],
          ),
        ),
        if (app.warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(app.warning!)),
                ],
              ),
            ),
          ),
        const SectionTitle(
          '¿Qué quieres personalizar?',
          subtitle: 'Especialidades de los negocios de nuestra comunidad.',
        ),
        LayoutBuilder(
          builder:
              (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in app.categories)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => onCategory(c.id),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  const {
                                        'estampado': Icons.checkroom_outlined,
                                        'bordado': Icons.auto_awesome_outlined,
                                        'impresion': Icons.print_outlined,
                                        'personalizados':
                                            Icons.card_giftcard_outlined,
                                      }[c.id] ??
                                      Icons.palette_outlined,
                                  color: scheme.primary,
                                  size: 28,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  c.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
        ),
        DataView<HomeOverview>(
          revision: app.revision,
          load: () => app.repository!.overview(),
          builder:
              (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(
                    'Todo bajo control',
                    subtitle: 'Actividad real de tu cuenta.',
                  ),
                  LayoutBuilder(
                    builder:
                        (context, constraints) => Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _Metric(
                              'Solicitudes',
                              data.requestsCount,
                              Icons.description_outlined,
                              (constraints.maxWidth - 20) / 3,
                              onExplore,
                            ),
                            _Metric(
                              'Propuestas',
                              data.quotesCount,
                              Icons.request_quote_outlined,
                              (constraints.maxWidth - 20) / 3,
                              onExplore,
                            ),
                            _Metric(
                              'En curso',
                              data.ordersCount,
                              Icons.inventory_2_outlined,
                              (constraints.maxWidth - 20) / 3,
                              onOrders,
                            ),
                          ],
                        ),
                  ),
                  const SectionTitle(
                    'Continúa tus encargos',
                    subtitle:
                        'Acuerdos activos, con su próxima fecha comprometida.',
                  ),
                  if (data.orders.isEmpty)
                    const EmptyState(
                      'Tu próximo acuerdo empieza aquí',
                      'Cuando aceptes o recibas una propuesta aceptada, podrás seguir su avance.',
                      icon: Icons.handshake_outlined,
                    ),
                  for (final order in data.orders) OrderCard(order),
                  SectionTitle(
                    p.isBusiness
                        ? 'Ideas esperando tu talento'
                        : 'Tus solicitudes recientes',
                  ),
                  if (data.requests.isEmpty)
                    EmptyState(
                      p.isBusiness
                          ? 'Sin oportunidades por ahora'
                          : 'Haz espacio para tu primera idea',
                      p.isBusiness
                          ? 'Revisa las categorías que atiendes desde Mi negocio.'
                          : 'Crea una solicitud y compártela con los negocios locales.',
                      icon: Icons.lightbulb_outline_rounded,
                    ),
                  for (final request in data.requests)
                    RequestCard(
                      request,
                      onTap:
                          () => openPage(
                            context,
                            RequestDetailScreen(request.id),
                          ),
                    ),
                ],
              ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final double width;
  final VoidCallback onTap;
  const _Metric(this.label, this.value, this.icon, this.width, this.onTap);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(height: 12),
              Text(
                '$value',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    ),
  );
}
