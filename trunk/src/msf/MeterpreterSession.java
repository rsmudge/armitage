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
		Iterator i = listeners.iterator();
		while (i.hasNext()) {
			((MeterpreterCallback)i.next()).commandComplete(session, command.token, response);
		}
	}

	public MeterpreterSession(RpcConnection connection, String session) {
		this.connection = connection;
		this.session = session;
		new Thread(this).start();
	}

	protected void processCommand(Command c) {
		Map response = null;
		int count = 0;
		try {
			response = (Map)connection.execute("session.meterpreter_write", new Object[] { session, Base64.encode(c.text) });
		
			/* white list any commands that don't return output */
			if (c.text.startsWith("cd "))
				return;

			Map read = readResponse();
			while ("".equals(read.get("data")) || read.get("data").toString().startsWith("[-] Error running command read")) {
				Thread.sleep(10);
				read = readResponse();
				count++;

				if (count > 1000) {
					System.err.println(session + " -> " + c.text + " ( " + response + ") - holding things up :(");
					break;
				}
			}

			/* process the read command ... */
			fireEvent(c, read);

			/* grab any additional readable data */
			Thread.sleep(50);
			read = readResponse();
			while (!"".equals(read.get("data"))) {
				System.err.println("Firing additional event: " + c.text + " (" + read + ")");
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
		while (true) {
			try {
				Command next = grabCommand();
				if (next == null) {
					Thread.sleep(50);
				}
				else {
					processCommand(next);
				}
			}
			catch (Exception ex) {
				ex.printStackTrace();
			}
		}
	}

	private Map readResponse() throws Exception {
		return (Map)(connection.execute("session.meterpreter_read", new Object[] { session }));
	}
}
