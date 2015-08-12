package ui;

import javax.swing.*;
import javax.swing.event.*;

import java.awt.*;
import java.awt.event.*;

import java.util.*;

import armitage.ArmitageApplication;
import msf.*;

/* A class to host multiple Armitage instances in one frame. Srsly */
public class MultiFrame extends JFrame implements KeyEventDispatcher {
	protected JToolBar            toolbar;
	protected JPanel              content;
	protected CardLayout          cards;
	protected LinkedList          buttons;
	protected Properties          prefs;

	private static class ArmitageInstance {
		public ArmitageApplication app;
		public JToggleButton       button;
		public RpcConnection       client;
		public boolean             serviced = false;
	}

	public void actOnDisconnect(final ArmitageInstance i) {
		if (i.serviced) {
			return;
		}

		i.serviced = true;

		SwingUtilities.invokeLater(new Runnable() {
			public void run() {
				i.button.setForeground(Color.RED);
				i.app.disconnected();
			}
		});
	}

	protected Set idle = new HashSet();

	public void actOnIdle(final ArmitageInstance i) {
		if (idle.contains(i)) { return; }

		idle.add(i);

		SwingUtilities.invokeLater(new Runnable() {
			public void run() {
				i.button.setForeground(Color.MAGENTA);
			}
		});
	}

	public void actOnNotIdle(final ArmitageInstance i) {
		idle.remove(i);

		SwingUtilities.invokeLater(new Runnable() {
			public void run() {
				i.button.setForeground(Color.BLACK);
			}
		});
	}

	public void watchDog() {
		/* watch for any disconnected sessions and warn the user */
		new Thread(new Runnable() {
			public void run() {
				while (true) {
					synchronized (buttons) {
						Iterator i = buttons.iterator();
						while (i.hasNext()) {
							ArmitageInstance temp = (ArmitageInstance)i.next();
							if (!((Async)temp.client).isConnected()) {
								actOnDisconnect(temp);
							}
							else if (!((Async)temp.client).isResponsive()) {
								actOnIdle(temp);
							}
							else if (idle.contains(temp)) {
								actOnNotIdle(temp);
							}
						}
					}

					try {
						Thread.sleep(1000);
					}
					catch (Exception ex) {}
				}
			}
		}).start();
	}

	public void setPreferences(Properties prefs) {
		this.prefs = prefs;
	}

	public Properties getPreferences() {
		return prefs;
	}

	public Map getClients() {
		synchronized (buttons) {
			Map r = new HashMap();

			Iterator i = buttons.iterator();
			while (i.hasNext()) {
				ArmitageInstance temp = (ArmitageInstance)i.next();
				/* only return clients that are connected AND responsive */
				if (((Async)temp.client).isConnected() && ((Async)temp.client).isResponsive()) {
					r.put(temp.button.getText(), temp.client);
				}
			}
			return r;
		}
	}

	public void setTitle(ArmitageApplication app, String title) {
		if (active == app)
			setTitle(title);
	}

	protected ArmitageApplication active;

	/* is localhost running? */
	public boolean checkLocal() {
		return checkCollision("localhost");
	}


	/* is localhost running? */
	public boolean checkCollision(String name) {
		synchronized (buttons) {
			Iterator i = buttons.iterator();
			while (i.hasNext()) {
				ArmitageInstance temp = (ArmitageInstance)i.next();
				if (name.equals(temp.button.getText())) {
					return true;
				}
			}
			return false;
		}
	}

	public boolean dispatchKeyEvent(KeyEvent ev) {
		if (active != null) {
			return active.getBindings().dispatchKeyEvent(ev);
		}
		return false;
	}

	public static final void setupLookAndFeel() {
		try {
			for (UIManager.LookAndFeelInfo info : UIManager.getInstalledLookAndFeels()) {
				if ("Nimbus".equals(info.getName())) {
					UIManager.setLookAndFeel(info.getClassName());
					break;
				}
			}
		}
		catch (Exception e) {
		}
	}

	public void closeConnect() {
		synchronized (buttons) {
			if (buttons.size() == 0) {
				System.exit(0);
			}
		}
	}

	public void quit() {
		synchronized (buttons) {
			ArmitageInstance temp = null;
			content.remove(active);
			Iterator i = buttons.iterator();
			while (i.hasNext()) {
				temp = (ArmitageInstance)i.next();
				if (temp.app == active) {
					toolbar.remove(temp.button);
					i.remove();
					toolbar.validate();
					toolbar.repaint();
					break;
				}
			}

			if (buttons.size() == 0) {
				System.exit(0);
			}
			else if (buttons.size() == 1) {
				remove(toolbar);
				validate();
			}

			if (i.hasNext()) {
				temp = (ArmitageInstance)i.next();
			}
			else {
				temp = (ArmitageInstance)buttons.getFirst();
			}

			set(temp.button);
		}
	}

	public MultiFrame() {
		super("");

		setLayout(new BorderLayout());

		/* setup our toolbar */
		toolbar = new JToolBar();

		/* content area */
		content = new JPanel();
		cards   = new CardLayout();
		content.setLayout(cards);

		/* setup our stuff */
		add(content, BorderLayout.CENTER);

		/* buttons?!? :) */
		buttons = new LinkedList();

		/* do this ... */
		setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);

		/* some basic setup */
		setSize(800, 600);
		setExtendedState(JFrame.MAXIMIZED_BOTH);

		/* all your keyboard shortcuts are belong to me */
		KeyboardFocusManager.getCurrentKeyboardFocusManager().addKeyEventDispatcher(this);

		/* start our thread to watch for disconnected session */
		watchDog();
	}

	protected void set(JToggleButton button) {
		synchronized (buttons) {
			/* set all buttons to the right state */
			Iterator i = buttons.iterator();
			while (i.hasNext()) {
				ArmitageInstance temp = (ArmitageInstance)i.next();
				if (temp.button.getText().equals(button.getText())) {
					temp.button.setSelected(true);
					active = temp.app;
					setTitle(active.getTitle());
				}
				else {
					temp.button.setSelected(false);
				}
			}

			/* show our cards? */
			cards.show(content, button.getText());
			active.touch();
		}
	}

	public void addButton(String title, final ArmitageApplication component, RpcConnection conn) {
		/* check if there's another button with the same name */
		if (checkCollision(title)) {
			addButton(title + " (2)", component, conn);
			return;
		}

		synchronized (buttons) {
			final ArmitageInstance a = new ArmitageInstance();
			a.button = new JToggleButton(title);
			a.button.setToolTipText(title);
			a.app    = component;
			a.client = conn;

			a.button.addActionListener(new ActionListener() {
				public void actionPerformed(ActionEvent ev) {
					set((JToggleButton)ev.getSource());
				}
			});

			a.button.addMouseListener(new MouseAdapter() {
				public void check(MouseEvent ev) {
					if (ev.isPopupTrigger()) {
						final JToggleButton source = a.button;
						JPopupMenu popup = new JPopupMenu();
						JMenuItem  rename = new JMenuItem("Rename");
						rename.addActionListener(new ActionListener() {
							public void actionPerformed(ActionEvent ev) {
								String name = JOptionPane.showInputDialog("Rename to?", source.getText());
								if (name != null) {
									content.remove(component);
									content.add(component, name);
									source.setText(name);
									set(source);
								}
							}
						});
						popup.add(rename);
						popup.show((JComponent)ev.getSource(), ev.getX(), ev.getY());
						ev.consume();
					}
				}

				public void mouseClicked(MouseEvent ev) {
					check(ev);
				}

				public void mousePressed(MouseEvent ev) {
					check(ev);
				}

				public void mouseReleased(MouseEvent ev) {
					check(ev);
				}
			});

			toolbar.add(a.button);
			content.add(component, title);
			buttons.add(a);
			set(a.button);

			if (buttons.size() == 1) {
				show();
			}
			else if (buttons.size() == 2) {
				add(toolbar, BorderLayout.SOUTH);
			}
			validate();
		}
	}
}
