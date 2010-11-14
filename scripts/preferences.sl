#
# Preferences
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

global('$preferences');

sub loadPreferences {
	local('$file $prefs');
	$file = getFileProper(systemProperties()["user.home"], ".armitage.prop");
	$prefs = [new Properties];
	if (-exists $file) {
		[$prefs load: [new java.io.FileInputStream: $file]];
	}
	else {
		[$prefs load: resource("resources/armitage.prop")];
	}
	return $prefs;
}

sub savePreferences {
	local('$file');
	$file = getFileProper(systemProperties()["user.home"], ".armitage.prop");
	[$preferences save: [new java.io.FileOutputStream: $file], "Armitage Configuration"];
}

$preferences = loadPreferences();

sub makePrefModel {
	local('$key $value $component $name $type $model');
	$model = [new GenericTableModel: @("component", "name", "type", "value"), "name", 32];
	[$model setCellEditable: 3];
	
	foreach $key => $value (convertAll($preferences)) {
		($component, $name, $type) = split('\\.', $key);
		[$model addEntry: %(component => $component, name => $name, type => $type, value => $value)];
	}
	return $model;
}

# $select = [new JComboBox: @("Font", "Monospaced", "Courier New", "Courier")];
# $style  = [new JComboBox: @("Style", "Bold", "Italic", "Bold/Italic")];
# $size   = [new JComboBox: @("Size")];

sub selectListener {
	local('$f_font $f_style $f_size $describe');
	$f_font  = [$select getSelectedItem];
	$f_style = strrep(uc([$style getSelectedItem]), ' + ', '');
	$f_size  = [$size getSelectedItem];

	$describe = "$f_font $+ - $+ $f_style $+ - $+ $f_size";
	[$preview setFont: [Font decode: $describe]];
	[$dialog pack];
	return $describe;
}

sub createPreferencesTab {
	local('$table $model $panel $sorter $model $l');

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$model = makePrefModel();

	$table = [new JTable: $model];
	$sorter = [new TableRowSorter: $model];
	[$table setRowSorter: $sorter];

	# allow only one row to be selected at a time.
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];
	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	[$table addMouseListener: lambda({
		if ($0 eq 'mouseClicked' && [$1 getClickCount] >= 2) {
			local('$sel $type $color $row $value');
			$sel  = [$model getSelectedValue: $table];
			$type = [$model getSelectedValueFromColumn: $table, "type"];
			$row = [$model getSelectedRow: $table];
			$value = [$model getSelectedValueFromColumn: $table, "value"];

			if ($type eq "color") {
				$color = [JColorChooser showDialog: $table, "pick a color", [Color decode: iff($value eq "", "#000000", $value)]];
	
				if ($color !is $null) {
					[$model setValueAtRow: $row, "value", '#' . substr(formatNumber(uint([$color getRGB]), 10, 16), 2)];
					[$model fireListeners];
				}
			}
			else if ($type eq "font") {
				local('$dialog $select $style $size $ok $cancel $preview $graphics $l $font $_style');
				$dialog = dialog("Choose a font", 640, 240);
				[$dialog setLayout: [new BorderLayout]];

				$font = [Font decode: $value];

				$graphics = [GraphicsEnvironment getLocalGraphicsEnvironment];

				# style..
				if ([$font isItalic] && [$font isBold]) { $_style = "Bold + Italic"; }
				else if ([$font isItalic]) { $_style = "Italic"; }
				else if ([$font isBold]) { $_style = "Bold"; }
				else { $_style = "Plain"; }

				$select = select([$graphics getAvailableFontFamilyNames], [$font getFamily]);
				$style  = select(@("Plain", "Bold", "Italic", "Bold + Italic"), $_style);
				$size   = select(@(5, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 23, 26, 30, 33, 38), [$font getSize] . "");

				$preview = [new JLabel: "nEWBS gET p0WNED by km-r4d h4x0rz"];

				$l = lambda(&selectListener, \$select, \$style, \$size, \$preview, \$dialog);
				map(lambda({ [$1 addItemListener: $l]; }, \$l), @($select, $style, $size));
				[$l];
			
				$ok = [new JButton: "Ok"];
				[$ok addActionListener: lambda({
					local('$font');
					[$model setValueAtRow: $row, "value", [$l]];
					[$model fireListeners];
					[$dialog setVisible: 0];
				}, \$dialog, \$model, \$row, \$l)];

				$cancel = [new JButton: "Cancel"];
				[$cancel addActionListener: lambda({ [$dialog setVisible: 0]; }, \$dialog)];

				[$dialog add: center($select, $style, $size), [BorderLayout NORTH]];
				[$dialog add: center($preview)];
				[$dialog add: center($ok, $cancel), [BorderLayout SOUTH]];
				[$dialog pack];
				[$dialog setVisible: 1];
			}
			else if ($type eq "shortcut") {
				local('$dialog $label');
				$dialog = dialog("Shortcut", 100, 100);
				$label = [new JLabel: "Type the desired key:"];
				[$dialog add: $label];
				[$dialog pack];

				[$label setFocusTraversalKeys: [KeyboardFocusManager FORWARD_TRAVERSAL_KEYS], [new HashSet]];
				[$label setFocusTraversalKeys: [KeyboardFocusManager BACKWARD_TRAVERSAL_KEYS], [new HashSet]];
				[$label setFocusTraversalKeys: [KeyboardFocusManager UP_CYCLE_TRAVERSAL_KEYS], [new HashSet]];

				[$label addKeyListener: lambda({
					if ($0 eq "keyReleased") {
						[$model setValueAtRow: $row, "value", strrep([KeyStroke getKeyStrokeForEvent: $1], 'released', 'pressed')];
						[$model fireListeners];
						[$dialog setVisible: 0];
					}
				}, \$dialog, \$model, \$row)];

				[$dialog setVisible: 1];
				[$label requestFocus];
			}
		}
	}, \$model, \$table)];

	local('$button');
	$button = [new JButton: "Save"];
	[$button addActionListener: lambda({
		local('$row $component $name $type $value');
		$preferences = [new Properties];
		foreach $row (convertAll([$model getRows])) {
			($component, $name, $type, $value) = values($row, @('component', 'name', 'type', 'value'));
			[$preferences setProperty: "$component $+ . $+ $name $+ . $+ $type", $value];
		}
		savePreferences();
		showError("Preferences saved.");
	}, \$model)];

	[$panel add: center($button), [BorderLayout SOUTH]];

	local('$dialog');
	$dialog = dialog("Preferences", 640, 480);
	[$dialog add: $panel, [BorderLayout CENTER]];
	[$button addActionListener: lambda({ [$dialog setVisible: 0]; }, \$dialog)];
	[$dialog setVisible: 1];

#	[$frame addTab: "Preferences", $panel, $null];
}
