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

	private static class Command {
		public Object   token;
		public String   text;
	}

	public static interface MeterpreterCallback {
		public void commandComplete(String session, Object token, Map response);
	}

	public void addListener(MeterpreterCallback l) {
		listeners.add(l);
	}

	public void fireEvent(Command command, Map response) {
		//try {
		//	System.err.println("Read: " + new String(Base64.decode(response.get("data") + ""), "UTF-8"));
		//}
		//catch (Exception ex) { }

		Iterator i = listeners.iterator();
		while (i.hasNext()) {
			((MeterpreterCallback)i.next()).commandComplete(session, command != null ? command.token : null, response);
		}
	}

	public MeterpreterSession(RpcConnection connection, String session) {
		this.connection = connection;
		this.session = session;
		new Thread(this).start();
	}

	protected void emptyRead() {
		try {
			Map read = readResponse();
			while (!"".equals(read.get("data"))) {
				fireEvent(null, read);
				//System.err.println("Orphaned event:\n" + new String(Base64.decode(read.get("data") + ""), "UTF-8"));
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
		long maxwait = 12000;
		int expectedReads = 1;
		try {
			emptyRead();
			//System.err.println("Processing: " + c.text);
			response = (Map)connection.execute("session.meterpreter_write", new Object[] { session, Base64.encode(c.text) });
		
			/* white list any commands that are not expected to return output */
			if (c.text.startsWith("cd "))
				return;

			if (c.text.startsWith("rm "))
				return;

			if (c.text.equals("shell\n") || c.text.equals("exit\n"))
				return;

			if (c.text.startsWith("webcam_snap ")) {
				expectedReads = 3;
			}
			else if (c.text.startsWith("download ")) {
				expectedReads = 2;
			}
			else if (c.text.startsWith("upload ")) {
				expectedReads = 2;
			}

			for (int x = 0; x < expectedReads; x++) {
				read = readResponse();
				start = System.currentTimeMillis();
				while ("".equals(read.get("data")) || read.get("data").toString().startsWith("[-] Error running command read")) {
					/* our goal here is to timeout any command after 10 seconds if it returns nothing */
					if ((System.currentTimeMillis() - start) > maxwait) {
						System.err.println("(" + session + ") - '" + c.text + "' - timed out");
						return;
					}

					Thread.sleep(100);
					read = readResponse();
				}

				/* process the read command ... */
				fireEvent(c, read);
			}

			/* grab any additional readable data */
			Thread.sleep(50);
			read = readResponse();
			while (!"".equals(read.get("data"))) {
				//System.err.println("Additional event: "+c.text+"\n" + new String(Base64.decode(read.get("data") + ""), "UTF-8"));
				fireEvent(c, read);
				read = readResponse();
			}
		}
		catch (Exception ex) {
			System.err.println(session + " -> " + c.text + " ( " + response + ")");
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
				if (next == null && (System.currentTimeMillis() - lastRead) > 250) {
					lastRead = System.currentTimeMillis();
					emptyRead();
				}
				else if (next == null) {
					Thread.sleep(50);
				}
				else {
					processCommand(next);
				}
			}
			catch (Exception ex) {
				System.err.println("This session appears to be dead! " + session + ", " + ex);
				return;
			}
		}
	}

	private Map readResponse() throws Exception {
		return (Map)(connection.execute("session.meterpreter_read", new Object[] { session }));
	}
}
