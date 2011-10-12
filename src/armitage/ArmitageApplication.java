package armitage;

import javax.swing.*;
import javax.swing.event.*;
import java.awt.image.*;

import java.awt.*;
import java.awt.event.*;

import java.util.*;

import ui.*;

public class ArmitageApplication extends JFrame {
	protected JTabbedPane tabs = null;
	protected JSplitPane split = null;
	protected JMenuBar menus = new JMenuBar();
	protected ScreenshotManager screens = null;

	public void setScreenshotManager(ScreenshotManager m) {
		screens = m;
	}

	public void addMenu(JMenuItem menu) {
		menus.add(menu);
	}

	public JMenuBar getJMenuBar() {
		return menus;
	}

	public void _removeTab(JComponent component) {
		tabs.remove(component);
		tabs.validate();
	}

	public void removeTab(final JComponent tab) {
		if (SwingUtilities.isEventDispatchThread()) {
			_removeTab(tab);
		}
		else {
			SwingUtilities.invokeLater(new Runnable() {
				public void run() {
					_removeTab(tab);
				}
			});
		}
	}

	public void setTop(final JComponent top) {
		if (SwingUtilities.isEventDispatchThread()) {
			_setTop(top);
		}
		else {
			SwingUtilities.invokeLater(new Runnable() {
				public void run() {
					_setTop(top);
				}
			});
		}
	}

	public void _setTop(JComponent top) {
		split.setTopComponent(top);
		split.setDividerLocation(0.50);
		split.setResizeWeight(0.50);
		split.revalidate();
	}

	public void addTab(final String title, final JComponent tab, final ActionListener removeListener) {
		if (SwingUtilities.isEventDispatchThread()) {
			_addTab(title, tab, removeListener);
		}
		else {
			SwingUtilities.invokeLater(new Runnable() {
				public void run() {
					_addTab(title, tab, removeListener);
				}
			});
		}
	}

	private static class ApplicationTab {
		public String title;
		public JComponent component;
		public ActionListener removeListener;

		public String toString() {
			return title;
		}
	}

	protected LinkedList apptabs = new LinkedList();

	public void addAppTab(String title, JComponent component, ActionListener removeListener) {
		ApplicationTab t = new ApplicationTab();
		t.title = title;
		t.component = component;
		t.removeListener = removeListener;
		apptabs.add(t);
	}

	public void popAppTab(Component tab) {
		Iterator i = apptabs.iterator();
		while (i.hasNext()) {
			final ApplicationTab t = (ApplicationTab)i.next();
			if (t.component == tab) {
				tabs.remove(t.component);
				i.remove();

				/* pop goes the tab! */
				JFrame r = new JFrame(t.title);
				r.setIconImages(getIconImages());
				r.setLayout(new BorderLayout());
				r.add(t.component, BorderLayout.CENTER);
				r.pack();
				r.setVisible(true);

				r.addWindowListener(new WindowAdapter() {
					public void windowClosing(WindowEvent ev) {
						if (t.removeListener != null)
							t.removeListener.actionPerformed(new ActionEvent(ev.getSource(), 0, "close"));
					}
				});
			}
		}
	}

	public void removeAppTab(Component tab, String title, ActionEvent ev) {
		Iterator i = apptabs.iterator();
		while (i.hasNext()) {
			ApplicationTab t = (ApplicationTab)i.next();
			if (t.component == tab || t.title.equals(title)) {
				tabs.remove(t.component);

				if (t.removeListener != null)
					t.removeListener.actionPerformed(ev);

				i.remove();
			}
		}
	}

	public void _addTab(final String title, final JComponent tab, final ActionListener removeListener) {
		final Component component = tabs.add("", tab);
		final JLabel label = new JLabel(title + "   ");

		JPanel control = new JPanel();
		control.setOpaque(false);
		control.setLayout(new BorderLayout());
		control.add(label, BorderLayout.CENTER);

		if (tab instanceof Activity) {
			((Activity)tab).registerLabel(label);
		}

		JButton close = new JButton("X");
		close.setOpaque(false);
		close.setContentAreaFilled(false);
		close.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));
		control.add(close, BorderLayout.EAST);

		int index = tabs.indexOfComponent(component);
		tabs.setTabComponentAt(index, control);

		addAppTab(title, tab, removeListener);

		close.addMouseListener(new MouseAdapter() {
			public void check(MouseEvent ev) {
				if (ev.isPopupTrigger()) {
					JPopupMenu menu = new JPopupMenu();

					JMenuItem a = new JMenuItem("Open in window", 'O');
					a.addActionListener(new ActionListener() {
						public void actionPerformed(ActionEvent ev) {
							popAppTab(component);
						}
					});

					JMenuItem b = new JMenuItem("Close like tabs", 'C');
					b.addActionListener(new ActionListener() {
						public void actionPerformed(ActionEvent ev) {
							removeAppTab(null, title, ev);
						}
					});

					JMenuItem c = new JMenuItem("Save screenshot", 'S');
					c.addActionListener(new ActionListener() {
						public void actionPerformed(ActionEvent ev) {
							/* capture the current tab in an image */
							BufferedImage image = new BufferedImage(tab.getWidth(), tab.getHeight(), BufferedImage.TYPE_4BYTE_ABGR);
							Graphics g = image.getGraphics();
							tab.paint(g);

							if (screens != null) {
								screens.saveScreenshot(image, title);
							}
						}
					});

					menu.add(a);
					menu.add(c);
					menu.addSeparator();
					menu.add(b);

					menu.show((Component)ev.getSource(), ev.getX(), ev.getY());
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

		close.addActionListener(new ActionListener() {
			public void actionPerformed(ActionEvent ev) {
				if  ((ev.getModifiers() & ActionEvent.CTRL_MASK) == ActionEvent.CTRL_MASK) {
					popAppTab(component);
				}
				else if  ((ev.getModifiers() & ActionEvent.SHIFT_MASK) == ActionEvent.SHIFT_MASK) {
					removeAppTab(null, title, ev);
				}
				else {
					removeAppTab(component, null, ev);
				}
				System.gc();
			}
		}); 

		component.addComponentListener(new ComponentAdapter() {
			public void componentShown(ComponentEvent ev) {
				if (component instanceof Activity) {
					((Activity)component).resetNotification();
				}

				component.requestFocusInWindow();
				System.gc();
			}
		});

		tabs.setSelectedIndex(index);
		component.requestFocusInWindow();
	}

	public ArmitageApplication() {
		super("Armitage");
		tabs = new DraggableTabbedPane();
		setLayout(new BorderLayout());

		/* place holder */
		JPanel panel = new JPanel();

		/* add our menubar */
		add(menus, BorderLayout.NORTH);

		split = new JSplitPane(JSplitPane.VERTICAL_SPLIT, panel, tabs);
		split.setOneTouchExpandable(true);

		/* add our tabbed pane */
		add(split, BorderLayout.CENTER);

		/* ... */
		setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
	}
}
