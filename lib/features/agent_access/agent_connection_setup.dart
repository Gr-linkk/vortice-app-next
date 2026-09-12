import 'package:flutter/material.dart';
import 'package:vortice_app/core/constants.dart';

/// Setup values contain the app's public project key only. Connection secrets
/// remain in the existing one-time view and never enter generated examples.
class AgentConnectionSetup extends StatelessWidget {
  const AgentConnectionSetup({super.key, required this.es});
  final bool es;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(es ? 'Configurar y comprobar mi agente' : 'Set up and test my agent'),
    leading: const Icon(Icons.cable),
    childrenPadding: const EdgeInsets.all(16),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(es
          ? '1. Crea una clave para una sola flota con los permisos que necesites. Guárdala en la configuración privada del agente.'
          : '1. Create a key for one fleet with the permissions you need. Save it in your agent’s private settings.'),
      const SizedBox(height: 12),
      Text(es
          ? '2. En el equipo donde corre tu agente, guarda el conector server.mjs de Vortice Next e instala Node 22 o posterior. Añade un servidor MCP local que ejecute node con la ruta completa al archivo.'
          : '2. On the computer running your agent, save the Vortice Next server.mjs connector and install Node 22 or later. Add a local MCP server that runs node with the full path to that file.'),
      const SelectableText('https://github.com/Gr-linkk/vortice-app-next/tree/main/tools/agent-mcp'),
      const SizedBox(height: 12),
      Text(es ? 'Variables del servidor MCP' : 'MCP server environment'),
      SelectableText('VORTICE_NEXT_URL=${AppConstants.supabaseUrl}\nVORTICE_NEXT_PUBLIC_KEY=${AppConstants.supabaseAnonKey}\nVORTICE_AGENT_TOKEN=<${es ? 'tu clave privada' : 'your private connection key'}>'),
      const SizedBox(height: 12),
      Text(es
          ? '3. Reinicia la conexión en tu agente y pídele que ejecute vortice_connection_test. Debe responder connected: true y mostrar la flota, los permisos y la caducidad correctos.'
          : '3. Restart the connection in your agent and ask it to run vortice_connection_test. It should return connected: true with the correct fleet, permissions and expiry.'),
      const SizedBox(height: 12),
      Text(es
          ? '4. Actualiza esta pantalla para ver la última comprobación del agente. Una conexión MCP abierta por sí sola no confirma el acceso a Vortice. Si falla, revisa la clave, su caducidad y la empresa activa del autorizador.'
          : '4. Refresh this screen to see the agent’s last successful check. An open MCP connection alone does not confirm Vortice access. If it fails, check the key, its expiry and the authorizer’s active company.'),
      const SizedBox(height: 12),
      Text(es
          ? 'Las propuestas de asignación, horario y alcance aparecen en Agentes para revisión humana. Para retirar acceso, usa Desconectar junto a la conexión. Los datos ya entregados y los borradores válidos permanecen.'
          : 'Assignment, schedule and scope proposals appear in Agents for human review. To remove access, use Disconnect beside the connection. Data already delivered and valid drafts remain.'),
    ],
  );
}
