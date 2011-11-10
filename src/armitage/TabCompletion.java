package armitage;

import console.Console;
import msf.*;
import java.util.*;
import java.awt.*;
import java.awt.event.*;
import javax.swing.*;

/* A generic class to manage reading/writing to a console. Keeps the code simpler (although the Sleep code to do this is 
   simpler than this Java code. *sigh* */
public class TabCompletion {
	protected RpcConnection connection;
	protected Console       window;
	protected String        session;
	protected String        tabsCommand;

	/* state for the actual tab completion */
	protected String last      = null;
	protected Iterator tabs    = null;



	public Console getWindow() {
		return window;
	}

	public TabCompletion(Console window, RpcConnection connection, String session, String tabsCommand) {
		this.window = window;
		this.connection = connection;
		this.session = session;
		this.tabsCommand = tabsCommand;

		window.addActionForKey("pressed TAB", new AbstractAction() {
			public void actionPerformed(ActionEvent ev) {
				tabComplete(ev);
			}
		});
	}

	public void tabComplete(ActionEvent ev) {
		String text = window.getInput().getText();
		if (text.length() == 0)
			return;

		if (tabs != null && tabs.hasNext() && text.equals(last)) {
			last = (String)tabs.next();
			window.getInput().setText(last);
		}
		else {
			try {
				Map response = (Map)connection.execute(tabsCommand, new Object[] { session, text });

				if (response.get("tabs") == null)
					return;

				LinkedHashSet responses = new LinkedHashSet();

				/* cycle through all of our options, we want to split items up to the
				   first slash. We also want them to be unique and ordered (hence the
				   linked hash set */
				Collection options = (Collection)response.get("tabs");
				Iterator i = options.iterator();
				while (i.hasNext()) {
					String option = i.next() + "";

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
}
