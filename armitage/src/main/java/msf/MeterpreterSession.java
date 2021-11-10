package msf;

import java.util.*;
import java.awt.*;
import java.awt.event.*;

/* Implements a class for writing commands to meterpreter and firing an
   event when the command is successfully executed (with its output) */

public class MeterpreterSession implements Runnable {
	protected RpcConnection connection;
	protected LinkedList	listeners = new LinkedList();
	protected LinkedList    commands  = new LinkedList();
	protected String        session;
	protected boolean       teammode;

	public static long DEFAULT_WAIT = 120000;

	private static class Command {
		public Object   token;
		public String   text;
		public long	start = System.currentTimeMillis();
	}

	public static interface MeterpreterCallback {
		public void commandComplete(String session, Object token, Map response);
		public void commandTimeout(String session, Object token, Map response);
	}

	public void addListener(MeterpreterCallback l) {
		synchronized (this) {
			listeners.add(l);
		}
	}

	public void fireEvent(Command command, Map response, boolean timeout) {
		Iterator i;
		synchronized (this) {
			i = new LinkedList(listeners).iterator();
		}
		while (i.hasNext()) {
			if (timeout) {
				((MeterpreterCallback)i.next()).commandTimeout(session, command != null ? command.token : null, response);
			}
			else {
				((MeterpreterCallback)i.next()).commandComplete(session, command != null ? command.token : null, response);
			}
		}
	}

	public MeterpreterSession(RpcConnection connection, String session, boolean teammode) {
		this.connection = connection;
		this.session = session;
		this.teammode = teammode;
		new Thread(this).start();
	}

	protected void emptyRead() {
		if (teammode)
			return;

		try {
			Map read = readResponse();
			while (!"".equals(read.get("data"))) {
				fireEvent(null, read, false);
				read = readResponse();
			}
		}
		catch (Exception ex) {
			throw new RuntimeException(ex);
		}
	}

	protected void processCommand(Command c) {
		Map response = null, read = null;
		long start;
		int expectedReads = 1;
		try {
			emptyRead();
			response = (Map)connection.execute("session.meterpreter_write", new Object[] { session, c.text });

			/* white list any commands that are not expected to return output */
			if (c.text.startsWith("cd "))
				return;

			if (c.text.startsWith("rm "))
				return;

			if (c.text.equals("shell\n") || c.text.equals("exit\n") || c.text.equals("rev2self\n"))
				return;

			if (c.text.startsWith("webcam_snap -h")) {
				/* do nothing, this is legit */
			}
			else if (c.text.startsWith("webcam_snap ")) {
				expectedReads = 3;
			}
			else if (c.text.startsWith("webcam_list") && !teammode) {
				/* insert a dummy command... in case there are no cameras */
				connection.execute("session.meterpreter_write", new Object[] { session, "getdesktop\n" });
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("download ")) {
				expectedReads = 2;
			}
			else if (c.text.startsWith("upload ")) {
				expectedReads = 2;
			}
			else if (c.text.startsWith("keyscan_dump")) {
				expectedReads = 2;
			}
			else if (c.text.startsWith("migrate")) {
				expectedReads = 2;
			}
			else if (c.text.startsWith("hashdump")) {
				readUntilSuccessful(c, true);
				return;
			}
			else if (c.text.startsWith("ps") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("execute") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("route") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("sniffer_interfaces") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("sniffer_dump") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("use ") && !teammode) {
				readUntilSuccessful(c, false, "\n", 60000);
				return;
			}
			else if (c.text.startsWith("load ") && !teammode) {
				readUntilSuccessful(c, false, "\n", 60000);
				return;
			}
			else if (c.text.startsWith("run ") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("timestomp ") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("sysinfo") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("ipconfig") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("list_tokens") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("impersonate_token") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("add_user") && !teammode) {
				/* when -h [host] is specified, attempts to add a user on another
				   host. In this case, output is split into multiple chunks.
				   This applies to add_localgroup_user and add_group_user too. */
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("add_localgroup_user") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("add_group_user") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}
			else if (c.text.startsWith("kerberos")) {
				readUntilSuccessful(c, true, "\n\n", 10000);
				return;
			}
			else if (c.text.startsWith("livessp")) {
				readUntilSuccessful(c, true, "\n\n", 10000);
				return;
			}
			else if (c.text.startsWith("mimikatz_command")) {
				readUntilSuccessful(c, true);
				return;
			}
			else if (c.text.startsWith("msv")) {
				readUntilSuccessful(c, true, "\n\n", 10000);
				return;
			}
			else if (c.text.startsWith("ssp")) {
				readUntilSuccessful(c, true, "\n\n", 10000);
				return;
			}
			else if (c.text.startsWith("tspkg")) {
				readUntilSuccessful(c, true, "\n\n", 10000);
				return;
			}
			else if (c.text.startsWith("wdigest")) {
				readUntilSuccessful(c, true, "\n\n", 10000);
				return;
			}
			else if (c.text.startsWith("enumdesktops") && !teammode) {
				readUntilSuccessful(c, false);
				return;
			}

			for (int x = 0; x < expectedReads; x++) {
				read = readResponse();
				start = System.currentTimeMillis();
				while ("".equals(read.get("data")) || read.get("data").toString().startsWith("[-] Error running command read")) {
					/* our goal here is to timeout any command after 10 seconds if it returns nothing */
					if ((System.currentTimeMillis() - start) > DEFAULT_WAIT) {
						fireEvent(c, read, true);
						armitage.ArmitageMain.print_error("command timed out (session " + session + ") - '" + c.text + "'");
						return;
					}

					read = readResponse();
				}

				/* process the read command ... */
				fireEvent(c, read, false);
			}

			/* grab any additional readable data */
			read = readResponse();
			while (!"".equals(read.get("data"))) {
				fireEvent(c, read, false);
				read = readResponse();
			}
		}
		catch (Exception ex) {
			armitage.ArmitageMain.print_error("Meterpreter " + session + " error while executing '" + (c.text + "").trim() + "': " + ex.getMessage() + "\n\tlast response: " + response);
			ex.printStackTrace();
		}
	}

	public void addCommand(Object token, String text) {
		synchronized (this) {
			if (text.trim().equals("")) {
				return;
			}
			Command temp = new Command();
			temp.token = token;
			temp.text  = text;
			commands.add(temp);
		}
	}

	protected Command grabCommand() {
		synchronized (this) {
			return (Command)commands.pollFirst();
		}
	}

	public void run() {
		long lastRead = System.currentTimeMillis();

		while (true) {
			try {
				Command next = grabCommand();
				if (next == null && (System.currentTimeMillis() - lastRead) > 500) {
					lastRead = System.currentTimeMillis();
					emptyRead();
				}
				else if (next == null) {
					Thread.sleep(25);
				}
				else {
					lastRead = System.currentTimeMillis();
					processCommand(next);
				}
			}
			catch (Exception ex) {
				armitage.ArmitageMain.print_error("Meterpreter session " + session + " is dead: " + ex.getMessage());
				ex.printStackTrace();
				return;
			}
		}
	}

	private void readUntilSuccessful(Command c, boolean pieces) throws Exception {
		long timeout = pieces ? 3000 : 500;
		readUntilSuccessful(c, pieces, timeout);
	}

	private void readUntilSuccessful(Command c, boolean pieces, long timeout) throws Exception {
		readUntilSuccessful(c, pieces, null, timeout);
	}

	/* keep reading until we get no data for a set period... this is a more aggressive
	   alternate read strategy for commands that I can't predict the end point well */
	private void readUntilSuccessful(Command c, boolean pieces, String theend, long timeout) throws Exception {
		/* our first read gets the default wait period at least... */
		long start = System.currentTimeMillis() + DEFAULT_WAIT;

		StringBuffer buffer = new StringBuffer();
		Map read = null;

		/* keep reading until we see nothing (up to the timeout) */
		while ((System.currentTimeMillis() - start) < timeout) {
			read = readResponse();
			String data = read.get("data") + "";
			if (data.length() > 0) {
				if (pieces) {
					fireEvent(c, read, false);
				}
				else {
					buffer.append(data);
				}
				start = System.currentTimeMillis();

				/* should we stop? */
				if (theend != null && (data.toString().endsWith(theend) || data.startsWith("[-] Unknown command:"))) {
					break;
				}
			}
		}

		if (!pieces) {
			read.put("data", buffer.toString());
			fireEvent(c, read, false);
		}
	}

	private Map readResponse() throws Exception {
		try {
			Thread.sleep(10);
		}
		catch (Exception ex) {}
		return (Map)(connection.execute("session.meterpreter_read", new Object[] { session }));
	}
}
