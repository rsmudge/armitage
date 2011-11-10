package msf;

import java.util.*;
import java.sql.*;

import java.io.*;

import graph.Route;

/* implement the old MSF RPC database calls in a way Armitage likes */
public class DatabaseImpl implements RpcConnection  {
	protected Connection db;
	protected Map queries;
	protected String workspaceid = "0";
	protected String hFilter = null;
	protected String sFilter = null;
	protected Route  rFilter = null;
	protected String oFilter = null;

	private static String join(List items, String delim) {
		StringBuffer result = new StringBuffer();
		Iterator i = items.iterator();
		while (i.hasNext()) {
			result.append(i.next());
			if (i.hasNext()) {
				result.append(delim);
			}
		}
		return result.toString();
	}

	public void setWorkspace(String name) {
		try {
			List spaces = executeQuery("SELECT DISTINCT * FROM workspaces");
			Iterator i = spaces.iterator();
			while (i.hasNext()) {
				Map temp = (Map)i.next();
				if (name.equals(temp.get("name"))) {
					workspaceid = temp.get("id") + "";
					queries = build();
				}
			}
		}
		catch (Exception ex) {
			throw new RuntimeException(ex);
		}
	}

	public void setDebug(boolean d) {

	}

	public DatabaseImpl() {
		queries = build();
	}

	/* marshall the type into something we'd rather deal with */
	protected Object fixResult(Object o) {
		if (o instanceof java.sql.Timestamp) {
			return new Long(((Timestamp)o).getTime());
		}
		return o;
	}

	protected int executeUpdate(String query) throws Exception {
		Statement s = db.createStatement();
		return s.executeUpdate(query);
	}

	/* execute the query and return a linked list of the results..., whee?!? */
	protected List executeQuery(String query) throws Exception {
		List results = new LinkedList();

		Statement s = db.createStatement();
		ResultSet r = s.executeQuery(query);

		while (r.next()) {
			Map row = new HashMap();

			ResultSetMetaData m = r.getMetaData();
			int c = m.getColumnCount();
			for (int i = 1; i <= c; i++) {
				row.put(m.getColumnLabel(i), fixResult(r.getObject(i)));
			}

			results.add(row);
		}

		return results;
	}

	public List filterByRoute(List rows) {
		if (rFilter != null || oFilter != null) {
			Iterator i = rows.iterator();
			while (i.hasNext()) {
				Map entry = (Map)i.next();
				if (rFilter != null && entry.containsKey("address")) {
					if (!rFilter.shouldRoute(entry.get("address") + "")) {
						i.remove();
						continue;
					}
				}
				else if (rFilter != null && entry.containsKey("host")) {
					if (!rFilter.shouldRoute(entry.get("host") + "")) {
						i.remove();
						continue;
					}
				}

				if (oFilter != null && entry.containsKey("os_name")) {
					if ((entry.get("os_name") + "").toLowerCase().indexOf(oFilter) == -1) {
						i.remove();
					}
				}
			}
		}
		return rows;
	}

	public void connect(String dbstring, String user, String password) throws Exception {
		db = DriverManager.getConnection(dbstring, user, password);
		setWorkspace("default");
	}

	public Object execute(String methodName) throws IOException {
		return execute(methodName, new Object[0]);
	}

	protected Map build() {
		Map temp = new HashMap();

		temp.put("db.creds", "SELECT DISTINCT creds.*, hosts.address as host, services.name as sname, services.port as port, services.proto as proto FROM creds, services, hosts WHERE services.id = creds.service_id AND hosts.id = services.host_id AND hosts.workspace_id = " + workspaceid);

		/* db.creds2 exists to prevent duplicate entries for the stuff I care about */
		temp.put("db.creds2", "SELECT DISTINCT creds.user, creds.pass, hosts.address as host, services.name as sname, services.port as port, services.proto as proto, creds.ptype FROM creds, services, hosts WHERE services.id = creds.service_id AND hosts.id = services.host_id AND hosts.workspace_id = " + workspaceid);

		if (hFilter != null) {
			temp.put("db.hosts", "SELECT DISTINCT hosts.* FROM hosts, services, sessions WHERE hosts.workspace_id = " + workspaceid + " AND " + hFilter + " LIMIT 512");
		}
		else {
			temp.put("db.hosts", "SELECT DISTINCT hosts.* FROM hosts WHERE hosts.workspace_id = " + workspaceid + " LIMIT 512");
		}

		if (sFilter != null) {
			temp.put("db.services", "SELECT DISTINCT services.*, hosts.address as host FROM services, hosts, sessions WHERE hosts.id = services.host_id AND hosts.workspace_id = " + workspaceid + " AND " + sFilter + " LIMIT 12228");
		}
		else {
			temp.put("db.services", "SELECT DISTINCT services.*, hosts.address as host FROM services, hosts WHERE hosts.id = services.host_id AND hosts.workspace_id = " + workspaceid + " LIMIT 12228");
		}

		temp.put("db.loots", "SELECT DISTINCT loots.*, hosts.address as host FROM loots, hosts WHERE hosts.id = loots.host_id AND hosts.workspace_id = " + workspaceid);
		temp.put("db.workspaces", "SELECT DISTINCT * FROM workspaces");
		temp.put("db.notes", "SELECT DISTINCT notes.*, hosts.address as host FROM notes, hosts WHERE hosts.id = notes.host_id AND hosts.workspace_id = " + workspaceid);
		temp.put("db.clients", "SELECT DISTINCT clients.*, hosts.address as host FROM clients, hosts WHERE hosts.id = clients.host_id AND hosts.workspace_id = " + workspaceid);
		return temp;
	}

	public Object execute(String methodName, Object[] params) throws IOException {
		try {
			if (queries.containsKey(methodName)) {
				String query = queries.get(methodName) + "";
				Map result = new HashMap();

				if (methodName.equals("db.services") || methodName.equals("db.hosts")) {
					result.put(methodName.substring(3), filterByRoute(executeQuery(query)));
				}
				else {
					result.put(methodName.substring(3), executeQuery(query));
				}
				return result;
			}
			else if (methodName.equals("db.vulns")) {
				//List a = executeQuery("SELECT DISTINCT vulns.*, hosts.address as host, services.port as port, services.proto as proto FROM vulns, hosts, services WHERE hosts.id = vulns.host_id AND services.id = vulns.service_id");
				//List b = executeQuery("SELECT DISTINCT vulns.*, hosts.address as host FROM vulns, hosts WHERE hosts.id = vulns.host_id AND vulns.service_id IS NULL");
				List a = executeQuery("SELECT DISTINCT vulns.*, hosts.address as host, services.port as port, services.proto as proto, refs.name as refs FROM vulns, hosts, services, vulns_refs, refs WHERE hosts.id = vulns.host_id AND services.id = vulns.service_id AND vulns_refs.vuln_id = vulns.id AND vulns_refs.ref_id = refs.id AND hosts.workspace_id = " + workspaceid);
				List b = executeQuery("SELECT DISTINCT vulns.*, hosts.address as host, refs.name as refs FROM vulns, hosts, refs, vulns_refs WHERE hosts.id = vulns.host_id AND vulns.service_id IS NULL AND vulns_refs.vuln_id = vulns.id AND vulns_refs.ref_id = refs.id AND hosts.workspace_id = " + workspaceid);

				a.addAll(b);

				Map result = new HashMap();
				result.put("vulns", a);
				return result;
			}
			else if (methodName.equals("db.clear")) {
				executeUpdate("DELETE FROM hosts");
				executeUpdate("DELETE FROM services");
				executeUpdate("DELETE FROM events");
				executeUpdate("DELETE FROM notes");
				executeUpdate("DELETE FROM creds");
				executeUpdate("DELETE FROM loots");
				executeUpdate("DELETE FROM vulns");
				return new HashMap();
			}
			else if (methodName.equals("db.filter")) {
				/* I'd totally do parameterized queries if I wasn't building this
				   damned query dynamically. Hence it'll have to do. */
				Map values = (Map)params[0];

				rFilter = null;
				oFilter = null;

				List hosts = new LinkedList();
				List srvcs = new LinkedList();

				if ((values.get("session") + "").equals("1")) {
					hosts.add("sessions.host_id = hosts.id AND sessions.closed_at IS NULL");
					srvcs.add("sessions.host_id = hosts.id AND sessions.closed_at IS NULL");
				}

				if (values.containsKey("hosts") && (values.get("hosts") + "").length() > 0) {
					String h = values.get("hosts") + "";
					if (!h.matches("[0-9a-fA-F\\.:\\%\\_/]+")) {
						System.err.println("Host value did not validate!");
						return new HashMap();
					}
					rFilter = new Route(h);
				}

				if (values.containsKey("ports") && (values.get("ports") + "").length() > 0) {
					List ports = new LinkedList();
					List ports2 = new LinkedList();
					String[] p = (values.get("ports") + "").split(",\\s+");
					for (int x = 0; x < p.length; x++) {
						if (!p[x].matches("[0-9]+")) {
							return new HashMap();
						}

						ports.add("services.port = " + p[x]);
						ports2.add("s.port = " + p[x]);
					}
					hosts.add("services.host_id = hosts.id");
					hosts.add("(" + join(ports, " OR ") + ")");
				}

				if (values.containsKey("os") && (values.get("os") + "").length() > 0) {
					oFilter = (values.get("os") + "").toLowerCase();
				}

				if (hosts.size() == 0) {
					hFilter = null;
				}
				else {
					hFilter = join(hosts, " AND ");
				}

				if (srvcs.size() == 0) {
					sFilter = null;
				}
				else {
					sFilter = join(srvcs, " AND ");
				}

				queries = build();
				return new HashMap();
			}
			else if (methodName.equals("db.fix_creds")) {
				Map values = (Map)params[0];
				PreparedStatement stmt = null;
				stmt = db.prepareStatement("UPDATE creds SET ptype = 'smb_hash' WHERE creds.user = ? AND creds.pass = ?");
				stmt.setString(1, values.get("user") + "");
				stmt.setString(2, values.get("pass") + "");

				Map result = new HashMap();
				result.put("rows", new Integer(stmt.executeUpdate()));
				return result;
			}
			else if (methodName.equals("db.report_host")) {
				Map values = (Map)params[0];
				String host = values.get("host") + "";
				PreparedStatement stmt = null;

				if (values.containsKey("os_name") && values.containsKey("os_flavor")) {
					stmt = db.prepareStatement("UPDATE hosts SET os_name = ?, os_flavor = ?, os_sp = '' WHERE hosts.address = ? AND hosts.workspace_id = " + workspaceid);
					stmt.setString(1, values.get("os_name") + "");
					stmt.setString(2, values.get("os_flavor") + "");
					stmt.setString(3, host);
				}
				else if (values.containsKey("os_name")) {
					stmt = db.prepareStatement("UPDATE hosts SET os_name = ?, os_flavor = '', os_sp = '' WHERE hosts.address = ? AND hosts.workspace_id = " + workspaceid);
					stmt.setString(1, values.get("os_name") + "");
					stmt.setString(2, host);
				}
				else {
					return new HashMap();
				}

				Map result = new HashMap();
				result.put("rows", new Integer(stmt.executeUpdate()));
				return result;
			}
			else {
				System.err.println("Need to implement: " + methodName);
			}
		}
		catch (Exception ex) {
			System.err.println(ex);
			ex.printStackTrace();
		}

		return new HashMap();
	}
}
