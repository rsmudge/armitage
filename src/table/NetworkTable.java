package table;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.border.*;
import javax.swing.table.*;

import java.awt.*;
import java.awt.event.*;
import java.awt.image.*;

import java.util.*;
import ui.ATable;

import graph.Route;
import graph.GraphPopup;
import graph.Refreshable;

public class NetworkTable extends JComponent implements ActionListener, Refreshable {
	protected JScrollPane scroller = null;

	public void actionPerformed(ActionEvent ev) {
		isAlive = false;
	}

	public boolean isAlive() {
		return isAlive;
	}

	public Image getScreenshot() {
		BufferedImage image = new BufferedImage(getWidth(), getHeight(), BufferedImage.TYPE_4BYTE_ABGR);
		Graphics g = image.getGraphics();
		paint(g);
		g.dispose();
		return image;
	}

	protected boolean isAlive = true;

	protected GraphPopup popup = null;

	public void setGraphPopup(GraphPopup popup) {
		this.popup = popup;
	}

	public NetworkTable() {
		this(new Properties());
	}

	protected GenericTableModel model;
	protected JTable table;
	protected int    height;

	public NetworkTable(Properties display) {
		this.display = display;

		model = new GenericTableModel(new String[] { " ", "Address", "Label", "Description", "Pivot" }, "Address", 256);
		table = new ATable(model);
		TableRowSorter sorter = new TableRowSorter(model);
		sorter.toggleSortOrder(1);

		Comparator hostCompare = new Comparator() {
			public int compare(Object a, Object b) {
				long aa = Route.ipToLong(a + "");
				long bb = Route.ipToLong(b + "");

				if (aa > bb) {
					return 1;
				}
				else if (aa < bb) {
					return -1;
				}
				else {
					return 0;
				}
			}

			public boolean equals(Object a, Object b) {
				return (a + "").equals(b + "");
			}
		};

		sorter.setComparator(1, hostCompare);
		sorter.setComparator(4, hostCompare);

		table.setRowSorter(sorter);
		table.setColumnSelectionAllowed(false);

		setupWidths();

		height = table.getRowHeight();

		final TableCellRenderer parent = table.getDefaultRenderer(Object.class);
		final TableCellRenderer phear  = new TableCellRenderer() {
			public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int col) {
				JLabel component = (JLabel)parent.getTableCellRendererComponent(table, value, isSelected, false, row, col);
				float  size      = component.getFont().getSize2D() * zoom;

				if (col == 4 && Boolean.TRUE.equals(model.getValueAt(table, row, "Active"))) {
					component.setFont(component.getFont().deriveFont(Font.BOLD).deriveFont(size));
				}
				else if (col == 1 && !"".equals(model.getValueAt(table, row, "Description"))) {
					component.setFont(component.getFont().deriveFont(Font.BOLD).deriveFont(size));
				}
				else {
					component.setFont(component.getFont().deriveFont(Font.PLAIN).deriveFont(size));
				}

				String tip = model.getValueAt(table, row, "Tooltip") + "";

				if (tip.length() > 0) {
					component.setToolTipText(tip);
				}

				return component;
			}
		};

		table.getColumn("Address").setCellRenderer(phear);
		table.getColumn("Label").setCellRenderer(phear);
		table.getColumn("Description").setCellRenderer(phear);
		table.getColumn("Pivot").setCellRenderer(phear);

		table.getColumn(" ").setCellRenderer(new TableCellRenderer() {
			public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int col) {
				JLabel component = (JLabel)parent.getTableCellRendererComponent(table, value, isSelected, false, row, col);

				Image original = (Image)model.getImageAt(table, row, "Image", zoom);
				component.setIcon(new ImageIcon(original));
				component.setText("");

				String tip = model.getValueAt(table, row, "Tooltip") + "";

				if (tip.length() > 0) {
					component.setToolTipText(tip);
				}

				return component;
			}
		});

		table.addMouseListener(new MouseAdapter() {
			public void all(MouseEvent ev) {
				if (ev.isPopupTrigger()) {
					popup.showGraphPopup(getSelectedHosts(), ev);
					ev.consume();
				}
			}

			public void mouseClicked(MouseEvent ev) { all(ev); }
			public void mousePressed(MouseEvent ev) { all(ev); }
			public void mouseReleased(MouseEvent ev) { all(ev); }
		});

		setLayout(new BorderLayout());
		scroller = new JScrollPane(table);
		add(scroller, BorderLayout.CENTER);

		setupShortcuts();
        }

	public void setupWidths() {
		table.getColumn("Address").setPreferredWidth((int)(125 * zoom));
		table.getColumn("Label").setPreferredWidth((int)(125 * zoom));
		table.getColumn("Pivot").setPreferredWidth((int)(125 * zoom));
		table.getColumn(" ").setPreferredWidth((int)(32 * zoom));
		table.getColumn(" ").setMaxWidth((int)(32 * zoom));
		table.getColumn("Description").setPreferredWidth((int)(500 * zoom));
	}

	protected LinkedList rows = new LinkedList();

	public void setTransferHandler(TransferHandler t) {
		table.setTransferHandler(t);
	}

	public void start() {
	}

	public void fixSelection(int rows[]) {
		if (rows.length == 0)
			return;

		table.getSelectionModel().setValueIsAdjusting(true);

		int rowcount = table.getModel().getRowCount();

		for (int x = 0; x < rows.length; x++) {
			if (rows[x] < rowcount) {
				table.getSelectionModel().addSelectionInterval(rows[x], rows[x]);
			}
		}

		table.getSelectionModel().setValueIsAdjusting(false);

	}

	public void end() {
		final int[] selected = table.getSelectedRows();

		model.clear(rows.size());
		Iterator i = rows.iterator();
		while (i.hasNext()) {
			model.addEntry((Map)i.next());
		}
		rows.clear();

		if (SwingUtilities.isEventDispatchThread()) {
			SwingUtilities.invokeLater(new Runnable() {
				public void run() {
					model.fireListeners();
					fixSelection(selected);
				}
			});
		}
		else {
			model.fireListeners();
			fixSelection(selected);
		}
	}

	/** delete all nodes that were not "touched" since start() was last called */
	public void deleteNodes() {
	}

	protected Properties display;

	/** highlight a route (maybe to show it's in use...) */
	public void highlightRoute(String src, String dst) {
		Iterator i = rows.iterator();
		while (i.hasNext()) {
			Map temp = (Map)i.next();
			if (temp.get("Address").equals(dst) && temp.get("Pivot").equals(src)) {
				temp.put("Active", Boolean.TRUE);
			}
		}
	}

	/** show the meterpreter routes . :) */
	public void setRoutes(Route[] routes) {
		Iterator i = rows.iterator();
		while (i.hasNext()) {
			Map temp = (Map)i.next();
			for (int x = 0; x < routes.length; x++) {
				Route r = routes[x];
				if (r.shouldRoute(temp.get("Address") + ""))
					temp.put("Pivot", r.getGateway());
			}
		}
	}

	public String getCellAt(Point p) {
		String[] x = getSelectedHosts();
		if (x.length > 0) {
			return x[0];
		}
		return null;
	}

        public String[] getSelectedHosts() {
		Object[] sels = model.getSelectedValues(table);
		String[] vals = new String[sels.length];
		for (int x = 0; x < sels.length; x++) {
			vals[x] = sels[x] + "";
		}
		return vals;
        }

	public void setAutoLayout(String layout) {
	}

	public Object addNode(String id, String label, String description, Image image, String tooltip) {
		if (id == null || label == null)
			return null;

		HashMap map = new HashMap();
		map.put("Address", id);

		if (description.indexOf(id) > -1)
			description = description.substring(id.length());
		map.put("Label", label);
		map.put("Description", description);
		map.put("Tooltip", tooltip);
		map.put("Image", image);
		map.put(" ", tooltip);
		map.put("Pivot", "");
		map.put("Active", Boolean.FALSE);
		rows.add(map);
		return map;
	}

	protected float zoom = 1.0f;

        public void zoom(double factor) {
		if (factor == 0.0f)
			zoom = 1.0f;
		else
			zoom += factor;

		table.setRowHeight((int) Math.ceil(height * zoom));

		/* update table widths to reflect the zoom factor */
		table.getColumn("Address").setPreferredWidth((int)(125 * zoom));
		table.getColumn(" ").setMaxWidth((int)(32 * zoom));
		table.getColumn(" ").setPreferredWidth((int)(32 * zoom));

		validate();
        }

	private void setupShortcuts() {
		addActionForKeySetting("graph.zoom_in.shortcut", "ctrl pressed EQUALS", new AbstractAction() {
			public void actionPerformed(ActionEvent ev) {
				zoom(0.1);
			}
		});

		addActionForKeySetting("graph.zoom_out.shortcut", "ctrl pressed MINUS", new AbstractAction() {
			public void actionPerformed(ActionEvent ev) {
				zoom(-0.1);
			}
		});

		addActionForKeySetting("graph.zoom_reset.shortcut", "ctrl pressed 0", new AbstractAction() {
			public void actionPerformed(ActionEvent ev) {
				zoom(0.0);
			}
		});
	}

        public void addActionForKeyStroke(KeyStroke key, Action action) {
		table.getActionMap().put(key.toString(), action);
		table.getInputMap().put(key, key.toString());
        }

        public void addActionForKey(String key, Action action) {
                addActionForKeyStroke(KeyStroke.getKeyStroke(key), action);
        }

        public void addActionForKeySetting(String key, String dvalue, Action action) {
                KeyStroke temp = KeyStroke.getKeyStroke(display.getProperty(key, dvalue));
                if (temp != null) {
                        addActionForKeyStroke(temp, action);
                }
        }
}
