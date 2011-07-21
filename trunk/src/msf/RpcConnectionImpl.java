package msf;

import java.io.*;
import java.net.*;
import java.text.*;
import java.util.*;
import javax.xml.*;
import javax.xml.parsers.*;
import javax.xml.transform.*;
import javax.xml.transform.dom.*;
import javax.xml.transform.stream.*;
import org.w3c.dom.*;

/**
 * This is a modification of msfgui/RpcConnection.java by scriptjunkie. Taken from 
 * the Metasploit Framework Java GUI. 
 */
public class RpcConnectionImpl implements RpcConnection {
	private String rpcToken;
	private Map callCache = new HashMap();

	private Socket connection;
	private OutputStream sout; //socket output/input
	private InputStream sin;

	private PrintStream debug = null;

	public void setDebug(boolean d) {
		synchronized(this) {
			if (d && debug == null) {
				try {
					debug = new PrintStream("debug.log", "UTF-8");
					debug.println(System.currentTimeMillis() + "\tproperties\t" + System.getProperties());
				}
				catch (Exception ex) {
				}
			}
			else if (d && debug != null) {
				setDebug(false);
				setDebug(true);
			}
			else {
				try {
					if (debug != null) 
						debug.close();
				}
				catch (Exception ex) {
					// I don't really care about this...
				}
				finally {
					debug = null;
				}
			}
		}
	}

	/** Constructor sets up a connection and authenticates. */
	public RpcConnectionImpl(String username, String password, String host, int port, boolean secure, boolean debugf) {
		boolean haveRpcd = false;
		String message = "";
		try {
			if (secure) {
				System.err.println("Doing a secure socket!");
				connection = new SecureSocket(host, port).getSocket();
			}
			else {
				connection = new Socket(host, port);
			}
			sout = connection.getOutputStream();
			sin = connection.getInputStream();

			connection.setSoTimeout(0); /* prevent reads from timing out */

			setDebug(debugf);

			Object[] params = new Object[]{ username, password };
			Map results = exec("auth.login",params);

			rpcToken = results.get("token").toString();
			haveRpcd = results.get("result").equals("success");
		} 
		catch (RuntimeException rex) {
			throw rex;
		}
		catch (Exception ex) {
			throw new RuntimeException(ex);
		}
	}

	/** Destructor cleans up. */
	protected void finalize() throws Throwable {
		super.finalize();
		connection.close();
	}

	/** Method that sends a call to the server and received a response; only allows one at a time */
	protected Map exec (String methname, Object[] params) {
		try {
			synchronized(this) {
				writeCall(methname, params);
				Object response = readResp();
				if (response instanceof Map) {
					return (Map)response;
				}
				else {
					Map temp = new HashMap();
					temp.put("response", response);
					return temp;
				}
			}
		} 
		catch (RuntimeException rex) { 
			if (debug != null) {
				debug.println("Exception: " + rex.getMessage());
				rex.printStackTrace(debug);
				debug.println("");
			}

			throw rex;
		}
		catch (Exception ex) { 
			if (debug != null) {
				debug.println("Exception: " + ex.getMessage());
				ex.printStackTrace(debug);
				debug.println("");
			}
			throw new RuntimeException(ex);
		}
	}

	/** Creates an XMLRPC call from the given method name and parameters and sends it */
	protected void writeCall(String methname, Object[] params) throws Exception {
		Document doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().newDocument();
		Element methodCall = doc.createElement("methodCall");
		doc.appendChild(methodCall);
		Element methodName = doc.createElement("methodName");
		methodName.appendChild(doc.createTextNode(methname));
		methodCall.appendChild(methodName);
		Element paramsEl = doc.createElement("params");
		methodCall.appendChild(paramsEl);

		for (Object param : params) {
			Element paramEl = doc.createElement("param");
			Node valEl = doc.createElement("value");
			if (param instanceof Map) { //Reverse of the parseVal() struct-to-HashMap code
				Element structEl = doc.createElement("struct");
				for (Object entryObj : ((Map)param).entrySet()) {
					Map.Entry ent = (Map.Entry)entryObj;
					Element membEl = doc.createElement("member");
					Element nameEl = doc.createElement("name");
					nameEl.appendChild(doc.createTextNode(ent.getKey().toString()));
					membEl.appendChild(nameEl);
					Element subvalEl = doc.createElement("value");
					subvalEl.appendChild(doc.createTextNode(ent.getValue().toString()));
					membEl.appendChild(subvalEl);
					structEl.appendChild(membEl);
				}
				valEl.appendChild(structEl);
			}
			else if (param instanceof Integer) { 
				Element i4El = doc.createElement("i4");
				i4El.appendChild(doc.createTextNode(param.toString()));
				valEl.appendChild(i4El);
			}
			else {
				valEl.appendChild(doc.createTextNode(param.toString()));
			}
			paramEl.appendChild(valEl);
			paramsEl.appendChild(paramEl);
		}
		ByteArrayOutputStream bout = new  ByteArrayOutputStream();
		TransformerFactory.newInstance().newTransformer().transform(new DOMSource(doc), new StreamResult(bout));

		if (debug != null) {
			debug.print(System.currentTimeMillis() + "\twriteResp()\t");
			debug.println(bout.toString("UTF-8"));
		}

		sout.write(bout.toByteArray());
		sout.write(0);
	}

	/** Receives an XMLRPC response and converts to an object */
	protected Object readResp() throws Exception {
		//read bytes
		ByteArrayOutputStream cache = new ByteArrayOutputStream();
		int val;
		try {
			while ((val = sin.read()) != 0) {
				if (val == -1)
					throw new IOException("Stream died.");
				if (val >= 32 || val == 10 || val == 13)
					cache.write(val);
			}
		} 
		catch (IOException ex) {
			throw new RuntimeException("Error reading response: " + ex.getMessage());
		}

		if (debug != null) {
			debug.print(System.currentTimeMillis() + "\treadResp()\t");
			debug.println(cache.toString("UTF-8"));
		}

		//parse the response: <methodResponse><params><param><value>...
		DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
		dbf.setValidating(false);

		Document root = dbf.newDocumentBuilder().parse(new ByteArrayInputStream(cache.toByteArray()));

		if (!root.getFirstChild().getNodeName().equals("methodResponse"))
			throw new IOException("Error reading response: not a response.");

		Node methResp = root.getFirstChild();
		if (methResp.getFirstChild().getNodeName().equals("fault")) {
			if (debug != null)
				debug.println(System.currentTimeMillis() + "\tfault\t" + cache.toString());

			throw new IOException(methResp.getFirstChild()//fault 
					.getFirstChild() // value
					.getFirstChild() // struct
					.getLastChild() // member
					.getLastChild() // value
					.getTextContent());
		}

		Node params = methResp.getFirstChild();
		if (!params.getNodeName().equals("params"))
			throw new IOException("Error reading response: no params.");

		Node param = params.getFirstChild();
		if (!param.getNodeName().equals("param"))
			throw new IOException("Error reading response: no param.");

		Node value = param.getFirstChild();
		if (!value.getNodeName().equals("value"))
			throw new IOException("Error reading response: no value.");

		return parseVal(value);
	}

	/** Takes an XMLRPC DOM value node and creates a java object out of it recursively */
	private Object parseVal(Node submemb) throws IOException {
		Node type = submemb.getFirstChild();
		String typeName = type.getNodeName();
		if (typeName.equals("string")) {//<struct><member><name>jobs</name><value><struct/></value></member></struct>
			return type.getTextContent(); //String returns java string
		}
		else if (typeName.equals("array")) { //Array returns Object[]
			ArrayList arrgh = new ArrayList();
			Node data = type.getFirstChild();

			if(!data.getNodeName().equals("data"))
				throw new IOException("Error reading array: no data.");

			for(Node val = data.getFirstChild(); val != null; val = val.getNextSibling())
				arrgh.add(parseVal(val));

			return arrgh.toArray();
		}
		else if (typeName.equals("struct")) { //Struct returns a HashMap of name->value member pairs
			HashMap structmembs = new HashMap();
			for (Node member = type.getFirstChild(); member != null; member = member.getNextSibling()){
				if (!member.getNodeName().equals("member"))
					throw new IOException("Error reading response: non struct member.");

				Object name = null, membValue = null;
				//get each member and put into output map

				for (Node submember = member.getFirstChild(); submember != null; submember = submember.getNextSibling()) {
					if(submember.getNodeName().equals("name"))
						name = submember.getTextContent();
					else if (submember.getNodeName().equals("value"))
						membValue = parseVal(submember); //Value can be arbitrarily complex
				}
				structmembs.put(name, membValue);
			}
			return structmembs;
		}
		else if (typeName.equals("i4")) {
			return new Integer(type.getTextContent());
		}
		else if (typeName.equals("boolean")) {
			return new Boolean(type.getTextContent().equals("1"));
		}
		else if (typeName.equals("dateTime.iso8601")) {
			SimpleDateFormat sdf = new SimpleDateFormat("yyyyMMdd'T'HH:mm:ss");
			try {
				return sdf.parse(type.getTextContent());
			}
			catch(ParseException pex) {
				return type.getTextContent();
			}
		} 
		else {
			throw new IOException("Error reading val: unknown type " + typeName);
		}
	}

	/** Runs command with no args */
	public Object execute(String methodName) throws IOException {
		return execute(methodName, new Object[]{});
	}

	/** Adds token, runs command, and notifies logger on call and return */
	public Object execute(String methodName, Object[] params) throws IOException {
		Object[] paramsNew = new Object[params.length+1];
		paramsNew[0] = rpcToken;
		System.arraycopy(params, 0, paramsNew, 1, params.length);
		Object result = cacheExecute(methodName, paramsNew);
		return result;
	}
	/** Caches certain calls and checks cache for re-executing them.
	 * If not cached or not cacheable, calls exec. */
	private Object cacheExecute(String methodName, Object[] params) throws IOException {
		if (methodName.equals("module.info") || methodName.equals("module.options") || methodName.equals("module.compatible_payloads")) {
			StringBuilder keysb = new StringBuilder(methodName);

			for(int i = 1; i < params.length; i++)
				keysb.append(params[i].toString());

			String key = keysb.toString();
			Object result = callCache.get(key);

			if(result != null)
				return result;

			result = exec(methodName, params);
			callCache.put(key, result);
			return result;
		}
		return exec(methodName, params);
	}
}
