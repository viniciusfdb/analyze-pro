import 'package:analyzepro/screens/dashboard/financeiro/inadimplencia_page.dart';
import 'package:analyzepro/screens/dashboard/estoque/ruptura_percentual_page.dart';
import 'package:analyzepro/screens/dashboard/financeiro/contas_pagar_page.dart';
import 'package:analyzepro/screens/dashboard/financeiro/contas_receber_page.dart';
import 'package:analyzepro/screens/dashboard/metas/metas_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/comparativos/comparativo_faturamento_empresas_vendas_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/comparativos/comparativo_faturamento_por_empresa_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/comparativos/comparativo_faturamento_por_empresa_diario_page.dart';
import 'package:analyzepro/screens/dashboard/estoque/estoque_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/empresa_colaborador_page.dart';
import 'package:analyzepro/screens/home/home_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/top_produtos_vendidos_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/produtos_sem_venda_page.dart';
import 'package:analyzepro/screens/dashboard/tesouraria/fechamento_caixa_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/screens/dashboard/vendas/vendas_page.dart';
import 'package:analyzepro/services/access_control_wrapper.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/config_service.dart';
import 'package:analyzepro/screens/login/login_page.dart';
import 'package:provider/provider.dart';
import 'package:analyzepro/core/global_context.dart';
import 'package:analyzepro/screens/dashboard/compras/diferenca_pedido_nota_page.dart';
import 'package:analyzepro/screens/dashboard/estoque/produto_com_saldo_negativo_page.dart';


/// Verifica se as configurações de conexão já foram informadas.
Future<bool> configExists() async {
  final baseUrl = await ConfigService.getBaseUrl();
  return baseUrl != null && baseUrl.isNotEmpty;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authService = AuthService();
  final apiClient = ApiClient(authService);

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<ApiClient>.value(value: apiClient),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      navigatorKey: GlobalContext.navigatorKey,
      title: 'Analyze',
      theme: ThemeData.light().copyWith(
        splashColor: Colors.white,
        highlightColor: Colors.white,
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,           // fundo do menu branco
          surfaceTintColor: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.white, // remove Material3 lavender
          elevation: 0,
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) {
          final authService = Provider.of<AuthService>(context, listen: false);
          final apiClient = Provider.of<ApiClient>(context, listen: false);
          return LoginPage(
            authService: authService,
            apiClient: apiClient,
          );
        },
        '/home': (context) {
          final authService = Provider.of<AuthService>(context, listen: false);
          final apiClient = Provider.of<ApiClient>(context, listen: false);
          return AccessControlWrapper(
            child: const HomePage(),
            apiClient: apiClient,
            authService: authService,
          );
        },
        '/vendas': (_) => VendasPage(),
        '/comparativo_faturamento_empresas_vendas': (_) => ComparativoFaturamentoEmpresasVendas(),
        '/comparativo_faturamento_por_empresa': (_) => ComparativoFaturamentoEmpresas(),
        '/comparativo_faturamento_por_empresa_diario': (_) => ComparativoFaturamentoEmpresasDiario(),
        '/estoque_page': (_) => EstoquePage(),
        '/ruptura_percentual': (_) => const RupturaPercentualPage(),
        '/produtos_mais_vendidos': (_) => (TopProdutosVendidos()),
        '/contas_receber': (_) => ContasReceberPage(),
        '/contas_pagar': (_) => const ContasPagarPage(),
        '/inadimplencia': (_) => const InadimplenciaPage(),
        '/produtos_sem_venda': (_) => const ProdutosSemVendaPage(),
        '/fechamento_caixa': (_) => FechamentoCaixaPage(),
        '/metas': (_) => MetasPorEmpresaPage(),
        '/diferenca_pedido_nota': (_) => DiferencaPedidoNotaPage(),
        '/produto_com_saldo_negativo': (_) => const ProdutoComSaldoNegativoPage(),
        '/faturamento_colaborador': (_) => const EmpresaColaboradorPage(),
      },
    );
  }
}
