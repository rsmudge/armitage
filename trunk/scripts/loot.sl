#
# Loot browser (not yet complete... on hold until more post/ modules have loot)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

sub updateLootModel {
	local('$port $row $host $loots $entry');
	[$model clear: 16];

	$loots = call($client, "db.loots")["loots"];
	foreach $entry ($loots) {
		$entry["date"] = formatDate($entry["updated_at"] * 1000L, 'yyyy-MM-dd HH:mm:ss Z');
		$entry["type"] = $entry["ltype"];
		[$model addEntry: $entry];
	}
	[$model fireListeners];
}

sub showLoot {
	local('$dialog $v $button $refresh $text');
	$v = [$model getSelectedValue: $table];

	if ($v !is $null) {
		$dialog = [new JPanel];
		[$dialog setLayout: [new BorderLayout]];

		#$dialog = dialog("View Loot", 640, 480);
	
		$text = [new console.Display: $preferences];
		[$text setText: getFileContent($v)];
		[$text setFont: [Font decode: [$preferences getProperty: "console.font.font", "Monospaced BOLD 14"]]];
		[$text setForeground: [Color decode: [$preferences getProperty: "console.foreground.color", "#ffffff"]]];
		[$text setBackground: [Color decode: [$preferences getProperty: "console.background.color", "#000000"]]];

		$button = [new JButton: "Close"];
		[$button addActionListener: lambda({ [$dialog setVisible: 0]; }, \$dialog)];

		$refresh = [new JButton: "Refresh"];
		[$refresh addActionListener: lambda({ [$text setText: getFileContent($v)]; }, \$text, \$v)];

		[$dialog add: $text, [BorderLayout CENTER]];
		[$dialog add: center($refresh), [BorderLayout SOUTH]];
		[$frame addTab: "View", $dialog, $null];
		#[$dialog show];
	}	
}

sub createLootBrowser {
	local('$table $model $panel $refresh $view $sorter $host');

	$model = [new GenericTableModel: @("host", "type", "info", "date"), "path", 16];

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$table = [new JTable: $model];
	$sorter = [new TableRowSorter: $model];
        [$sorter toggleSortOrder: 0];
	[$sorter setComparator: 0, &compareHosts];
	[$sorter setComparator: 3, {
		return convertDate($1) <=> convertDate($2);
	}];
	[$table setRowSorter: $sorter];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	$view = [new JButton: "View"];

	[$table addMouseListener: lambda({
		if ($0 eq "mousePressed" && [$1 getClickCount] >= 2) {
			showLoot(\$model, \$table);
		}
	}, \$model, \$table)];

	[$view addActionListener: lambda({
		showLoot(\$model, \$table);
	}, \$model, \$table)];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		updateLootModel(\$model);	
	}, \$model)];

	updateLootModel(\$model); 		

	[$panel add: center($view, $refresh), [BorderLayout SOUTH]];

	[$frame addTab: "Loot", $panel, $null];
}
