package armitage;

import console.Console;
import msf.*;
import java.util.*;
import java.awt.*;
import java.awt.event.*;
import javax.swing.*;

/* A generic class to manage reading/writing to a console. Keeps the code simpler (although the Sleep code to do this is 
   simpler than this Java code. *sigh* */
public class ConsoleClient implements Runnable, ActionListener {
	protected RpcConnection connection;
	protected Console       window;
	protected String        readCommand;
	protected String        writeCommand;
	protected String        destroyCommand;
	protected String        session;
	protected LinkedList	listeners = new LinkedList();
	protected boolean       echo = true;
	protected boolean	go_read = true;

	public void kill() {
		synchronized (listeners) {
			go_read = false;
		}
	}

	public Console getWindow() {
		return window;
	}

	public void setEcho(boolean b) {
		echo = b;
	}

	public void setWindow(Console console) {
		synchronized (this) {
			window = console;
			setupListener();
		}
	}

	public void addSessionListener(ConsoleCallback l) {
		listeners.add(l);
	}

	public void fireSessionReadEvent(String text) {
		Iterator i = listeners.iterator();
		while (i.hasNext()) {
			((ConsoleCallback)i.next()).sessionRead(session, text);
		}
	}

	public void fireSessionWroteEvent(String text) {
		Iterator i = listeners.iterator();
		while (i.hasNext()) {
			((ConsoleCallback)i.next()).sessionWrote(session, text);
		}
	}

	public ConsoleClient(Console window, RpcConnection connection, String readCommand, String writeCommand, String destroyCommand, String session, boolean swallow) {
		this.window = window;
		this.connection = connection;
		this.readCommand = readCommand;
		this.writeCommand = writeCommand;
		this.destroyCommand = destroyCommand;
		this.session = session;

		setupListener();

		if (swallow) {
			try {
				readResponse();
			}
			catch (Exception ex) {
				System.err.println(ex);
			}
		}

		new Thread(this).start();
	}


	/* call this if the console client is referencing a metasploit console with tab completion */
	public void setMetasploitConsole() {
		window.addActionForKey("ctrl pressed Z", new AbstractAction() {
			public void actionPerformed(ActionEvent ev) {
				sendString("background\n");
			}
		});

		new TabCompletion(window, connection, session, "console.tabs");
	}

	/* called when the associated tab is closed */
	public void actionPerformed(ActionEvent ev) {
		if (destroyCommand != null) {
			new Thread(new Runnable() {
				public void run() {
					try {
						connection.execute(destroyCommand, new Object[] { session }); 
					}
					catch (Exception ex) {
						ex.printStackTrace();
					}
				}
			}).start();
		}
	}

	protected void finalize() {
		actionPerformed(null);
	}

	public void sendString(String text) {
		Map read = null;

		try {
			Map response = (Map)connection.execute(writeCommand, new Object[] { session, text });

			synchronized (this) {
				if (window != null && echo) {
					window.append(window.getPromptText() + text);
					if (! "".equals( response.get("prompt") )) {
						window.updatePrompt(cleanText(response.get("prompt") + ""));
					}
				}
			}

			read = readResponse();
			if ("false".equals(read.get("busy") + "") && "".equals(read.get("data") + "")) {
				//System.err.println("Should command be resent? " + text + " -- " + read);
			}
			else {
				processRead(read);
			}

			fireSessionWroteEvent(text);
		}
		catch (Exception ex) {
			ex.printStackTrace();
		}
	}

	protected void setupListener() {
		synchronized (this) {
			if (window != null) {
				window.getInput().addActionListener(new ActionListener() {
					public void actionPerformed(ActionEvent ev) {
						final String text = window.getInput().getText() + "\n";
						window.getInput().setText("");
						new Thread(new Runnable() {
							public void run() {
								sendString(text);
							}
						}).start();
					}
				});
			}
		}
	}

	public static String cleanText(String text) {
		StringBuffer string = new StringBuffer(text.length());
		char chars[] = text.toCharArray();
		for (int x = 0; x < chars.length; x++) {
			if (chars[x] != 1 && chars[x] != 2)
				string.append(chars[x]);
		}

		return string.toString();
	}

	private Map readResponse() throws Exception {
		return (Map)(connection.execute(readCommand, new Object[] { session }));
	}

	private long lastRead = 0L;

	private void processRead(Map read) throws Exception {
		if (! "".equals( read.get("data") )) {
			String text = read.get("data") + "";

			synchronized (this) {
				if (window != null)
					window.append(text);
			}
			fireSessionReadEvent(text);
			lastRead = System.currentTimeMillis();
		}

		synchronized (this) {
			if (! "".equals( read.get("prompt") ) && window != null) {
				window.updatePrompt(cleanText(read.get("prompt") + ""));
			}
		}
	}

	public void run() {
		Map read;
		boolean shouldRead = go_read;

		try {
			while (shouldRead) {
				read = readResponse();

				if (read == null || "failure".equals( read.get("result") + "" )) {
					break;
				}

				processRead(read);

				if ((System.currentTimeMillis() - lastRead) <= 500) {
					Thread.sleep(10);
				}
				else {
					Thread.sleep(500);
				}

				synchronized (listeners) {
					shouldRead = go_read;
				}
			}
		}
		catch (Exception javaSucksBecauseItMakesMeCatchEverythingFuckingThing) {
			javaSucksBecauseItMakesMeCatchEverythingFuckingThing.printStackTrace();
		}
	}
}
