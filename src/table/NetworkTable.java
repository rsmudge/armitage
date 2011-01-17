package table;

import javax.swing.*; 
import javax.swing.event.*; 
import javax.swing.border.*;
import javax.swing.table.*;

import java.awt.*; 
import java.awt.event.*;

import java.util.*;

import graph.Route;
import graph.GraphPopup;

public class NetworkTable extends JComponent implements ActionListener {
	public void actionPerformed(ActionEvent ev) {
		isAlive = false;
	}

	public boolean isAlive() {
		return isAlive;
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

	public NetworkTable(Properties display) {
		this.display = display;

		model = new GenericTableModel(new String[] { " ", "Address", "Description", "Pivot" }, "Address", 256);
		table = new JTable(model);
		TableRowSorter sorter = new TableRowSorter(model);
		sorter.toggleSortOrder(1);

		Comparator hostCompare = new Comparator() {
			public int compare(Object a, Object b) {
				return (int)(Route.ipToLong(a + "") - Route.ipToLong(b + ""));
			}

			public boolean equals(Object a, Object b) {
				return (a + "").equals(b + "");
			}
		};

		sorter.setComparator(1, hostCompare);
		sorter.setComparator(3, hostCompare);

		table.setRowSorter(sorter);
		table.setColumnSelectionAllowed(false);

		table.getColumn("Address").setPreferredWidth(125);
		table.getColumn("Pivot").setPreferredWidth(125);
		table.getColumn(" ").setPreferredWidth(32);
		table.getColumn(" ").setMaxWidth(32);
		table.getColumn("Description").setPreferredWidth(500);

		final TableCellRenderer parent = table.getDefaultRenderer(Object.class);
		table.setDefaultRenderer(Object.class, new TableCellRenderer() {
			public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int col) {
				JLabel component = (JLabel)parent.getTableCellRendererComponent(table, value, isSelected, false, row, col);

				if (col == 3 && Boolean.TRUE.equals(model.getValueAt(table, row, "Active"))) {
					component.setFont(component.getFont().deriveFont(Font.BOLD));
				}
				else if (col == 1 && !"".equals(model.getValueAt(table, row, "Description"))) {
					component.setFont(component.getFont().deriveFont(Font.BOLD));
				}
				else {
					component.setFont(component.getFont().deriveFont(Font.PLAIN));
				}

				String tip = model.getValueAt(table, row, "Tooltip") + "";

				if (tip.length() > 0) {
					component.setToolTipText(tip);
				}
				return component;
			}
		});

		table.getColumn(" ").setCellRenderer(new TableCellRenderer() {
			public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int col) {
				JLabel component = (JLabel)parent.getTableCellRendererComponent(table, value, isSelected, hasFocus, row, col);
				component.setIcon(new ImageIcon((Image)model.getValueAt(table, row, "Image")));
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
				}
			}

			public void mouseClicked(MouseEvent ev) { all(ev); }
			public void mousePressed(MouseEvent ev) { all(ev); }
			public void mouseReleased(MouseEvent ev) { all(ev); }
		});

		setLayout(new BorderLayout());
		add(new JScrollPane(table), BorderLayout.CENTER);
        }
	
	protected LinkedList rows = new LinkedList();

	public void start() {
	}

	public void fixSelection(int rows[]) {
		if (rows.length > 0) 
			table.setRowSelectionInterval(rows[0], rows[rows.length - 1] < table.getRowCount() ? rows[rows.length - 1] : table.getRowCount() - 1);
	}

	public void end() {
		final int[] selected = table.getSelectedRows();

		model.clear(rows.size());
		Iterator i = rows.iterator();
		while (i.hasNext()) {
			model.addEntry((Map)i.next());
		}
		rows.clear();
		model.fireListeners();

		if (SwingUtilities.isEventDispatchThread()) {
			SwingUtilities.invokeLater(new Runnable() {
				public void run() {
					fixSelection(selected);
				}
			});
		}
		else {
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

        public void addActionForKeySetting(String key, String dvalue, Action action) {
	}

	public Object addNode(String id, String label, Image image, String tooltip) {
		if (id == null || label == null)
			return null;

		HashMap map = new HashMap();
		map.put("Address", id);

		if (label.indexOf(id) > -1)
			label = label.substring(id.length());
		map.put("Description", label);
		map.put("Tooltip", tooltip);
		map.put("Image", image);
		map.put(" ", tooltip);
		map.put("Pivot", "");
		map.put("Active", Boolean.FALSE);
		rows.add(map);
		return map;
	}
}
