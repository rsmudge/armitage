package armitage;

import console.*;

import java.util.*;
import java.awt.*;
import java.awt.event.*;

import msf.*;
import java.math.*;
import java.security.*;

/* Implements a class for writing commands to a console and firing an event when the command is successfully executed
   (with its output). My hope is that this will replace the CommandClient class which likes to execute stuff out of order */
public class ConsoleQueue implements Runnable {
	protected RpcConnection connection;
	protected LinkedList    listeners = new LinkedList();
	protected LinkedList    commands  = new LinkedList();
	protected String        consoleid   = null;
	protected Console display = null;

	private static class Command {
		public Object   token;
		public String   text;
		public long	start = System.currentTimeMillis();
	}

	public static interface ConsoleCallback {
		public void commandComplete(String consoleid, Object token, String response);
	}

	public void addListener(ConsoleCallback l) {
		listeners.add(l);
	}

	public void fireEvent(Command command, String output) {
		if (command.token == null)
			return;

		Iterator i = listeners.iterator();
		while (i.hasNext()) {
			((ConsoleCallback)i.next()).commandComplete(consoleid, command != null ? command.token : null, output);
		}
	}

	public ConsoleQueue(RpcConnection connection) {
		this.connection = connection;
	}

	public boolean isEmptyData(String data) {
		return "".equals(data) || "null".equals(data);
	}

	protected void processCommand(Command c) {
		Map read = null;
		try {
			StringBuffer writeme = new StringBuffer();
			writeme.append(c.text);
			writeme.append("\n");

			/* absorb anything misc */
			readResponse();

			/* write our command to whateverz */
			connection.execute("console.write", new Object[] { consoleid, writeme.toString() });

			/* start collecting output */
			StringBuffer output = new StringBuffer();
			Thread.sleep(10);
			int count = 0;

			while ((read = (Map)(connection.execute("console.read", new Object[] { consoleid }))) != null) {
				String text = null;
				if (! isEmptyData( read.get("data") + "" )  ) {
					text = read.get("data") + "";
					output.append(text);

					if (display != null) {
						display.append(text);
					}
				}
				else if ("false".equals( read.get("busy") + "" ) && isEmptyData( read.get("data") + "" )) {
					/* this is a bug that annoys the hell out of me. Sometimes an
					   executed command is swallowed by metasploit. This is an attempt
					   to work around that by retrying the command once if nothing was
					   read in response to it. */

					if (count > 0) {
						break;
					}
					else {
						connection.execute("console.write", new Object[] { consoleid, writeme.toString() });
					}
				}
				else if ("failure".equals( read.get("result") + "" )) {
					break;
				}

				Thread.sleep(10);
				count++;
			}

			/* fire an event with our output */
			fireEvent(c, output.toString());
		}
		catch (Exception ex) {
			System.err.println(consoleid + " -> " + c.text + " ( " + read + ")");
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

	protected boolean stop = false;

	public void start() {
		new Thread(this).start();
	}

	public void stop() {
		synchronized (this) {
			stop = true;
		}
	}

	protected Command grabCommand() {
		synchronized (this) {
			return (Command)commands.pollFirst();
		}
	}

	/* keep grabbing commands, acquiring locks, until everything is executed */
	public void run() {
		try {
			Map read = (Map)connection.execute("console.create", new Object[] {});
			if (read.get("id") != null) {
				/* swallow the metasploit banner */
				connection.execute("console.read", new Object[] { read.get("id") + "" });
				consoleid = read.get("id") + "";
			}
			else {
				return;
			}

			while (!stop) {
				Command next = grabCommand();
				if (next != null) {
					processCommand(next);
					Thread.sleep(10);
				}
				else {
					Thread.sleep(250);
				}
			}

			connection.execute("console.destroy", new Object[] { consoleid });
		}
		catch (Exception ex) {
			System.err.println("This console appears to be dead! " + consoleid + ", " + ex);
			return;
		}
	}

        private Map readResponse() throws Exception {
		return (Map)(connection.execute("console.read", new Object[] { consoleid }));
        }
}
