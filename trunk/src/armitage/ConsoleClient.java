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

	public Console getWindow() {
		return window;
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

		window.addActionForKey("pressed TAB", new AbstractAction() {
			protected String last      = null;
			protected Iterator tabs    = null;

			public void actionPerformed(ActionEvent ev) {
				String text = window.getInput().getText();
	
				if (text.length() == 0)
					return;

				if (tabs != null && tabs.hasNext() && text.equals(last)) {
					last = (String)tabs.next();
					window.getInput().setText(last);
				}
				else {
					try {
						Map response = (Map)connection.execute("console.tabs", new Object[] { session, text });

						if (response.get("tabs") == null)
							return;

						LinkedHashSet responses = new LinkedHashSet();

						/* cycle through all of our options, we want to split items up to the
						   first slash. We also want them to be unique and ordered (hence the
						   linked hash set */
						Object[] options = (Object[])response.get("tabs");
						for (int x = 0; x < options.length; x++) {
							String option = options[x] + "";

							String begin; 
							String end; 

							if (text.length() > option.length()) {
								begin = option;
								end = "";
							}
							else {
								begin = option.substring(0, text.length());
								end = option.substring(text.length());							
							}					

							int nextSlash;
							if ((nextSlash = end.indexOf('/')) > -1 && (nextSlash + 1) < end.length()) {
								end = end.substring(0, nextSlash);
							}

							responses.add(begin + end);
						}

						responses.add(text);

						tabs = responses.iterator();
						last = (String)tabs.next();

						window.getInput().setText(last);
					}	
					catch (Exception ex) {
						ex.printStackTrace();
					}		
				}
			}
		});
	}

	/* called when the associated tab is closed */
	public void actionPerformed(ActionEvent ev) {
		try {
			if (destroyCommand != null)
				connection.execute(destroyCommand, new Object[] { session }); 
		}
		catch (Exception ex) {
			ex.printStackTrace();
		}
	}

	protected void finalize() {
		actionPerformed(null);
	}

	public void sendString(String text) {
		try {
			synchronized (this) {
				Map response = (Map)connection.execute(writeCommand, new Object[] { session, Base64.encode(text) });

				if (window != null) {
					window.append(window.getPromptText() + text);
					if (! "".equals( response.get("prompt") )) {
						window.updatePrompt(cleanText(new String(Base64.decode( response.get("prompt") + "" ), "UTF-8")));
					}
				}

				Map read = readResponse();
				if ("false".equals(read.get("busy") + "") && "".equals(read.get("data") + "")) {
					System.err.println("Sending: " + text + " again!");
					connection.execute(writeCommand, new Object[] { session, Base64.encode(text) });
				}
				else {
					processRead(read);
				}
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
						String text = window.getInput().getText() + "\n";
						sendString(text);
						window.getInput().setText("");
					}
				});
			}
		}
	}

	public String cleanText(String text) {
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

	private void processRead(Map read) throws Exception {
		if (! "".equals( read.get("data") )) {
			String text = new String(Base64.decode( read.get("data") + "" ), "UTF-8");
			if (window != null)
				window.append(text);
			fireSessionReadEvent(text);	
		}

		if (! "".equals( read.get("prompt") ) && window != null) {
			window.updatePrompt(cleanText(new String(Base64.decode( read.get("prompt") + "" ), "UTF-8")));
		}
	}

	public void run() {
		Map read;

		try {
			while (true) {
				synchronized (this) {
					read = readResponse();

					if (read == null || "failure".equals( read.get("result") + "" ))
						break;

					processRead(read);
				} 

				Thread.sleep(200);
			}
		}
		catch (Exception javaSucksBecauseItMakesMeCatchEverythingFuckingThing) {
			javaSucksBecauseItMakesMeCatchEverythingFuckingThing.printStackTrace();
		}
	}
}
