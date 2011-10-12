#
# This file defines the main GUI and loads additional modules
#

debug(7 | 34);

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.border.*;
import javax.swing.table.*;
import javax.swing.tree.*;
import javax.imageio.*;

import java.awt.*;
import java.awt.image.*;
import java.awt.event.*;

import graph.*;
import armitage.*;
import table.*;

# Create a new menu, returns the menu, you have to attach it to something
# menu([$parent], "Name", 'Accelerator')
sub menu {
	local('$menu');
	if (size(@_) == 2) {
		$menu = [new JMenu: $1];

		if ($2 !is $null) {
			[$menu setMnemonic: casti(charAt($2, 0), 'c')];
		}
	}
	else {
		$menu = invoke(&menu, sublist(@_, 1));
		[$1 add: $menu];
	}
	return $menu;
}

# create a separator in the parent menu
sub separator {
	[$1 addSeparator];
}

# create a menu item, attaches it to the specified parent (based on the Name)
# item($parent, "Name", 'accelerator', &listener)
sub item {
	local('$item');
	$item = [new JMenuItem: $2];
	if ($3 !is $null) {
		[$item setMnemonic: casti(charAt($3, 0), 'c')];
	}
	
	if ($4 is $null) { warn("Incomplete: " . @_); }

	[$item addActionListener: lambda({ 
		invoke($function);
	}, $function => $4)];

	[$1 add: $item];
	return $item;
}

sub dispatchEvent {
	if ([SwingUtilities isEventDispatchThread]) {
		[$1];
	}
	else {
		[SwingUtilities invokeLater: $1];
	}
}

sub showError {
	dispatchEvent(lambda({
		[JOptionPane showMessageDialog: $frame, $message];
	}, $message => $1));
}

sub ask {
	return [JOptionPane showInputDialog: $1];
}

# askYesNo("title", "text")
sub askYesNo {
	return [JOptionPane showConfirmDialog: $null, $1, $2, [JOptionPane YES_NO_OPTION]];
}

sub chooseFile {
	local('$fc $file $title $sel $dir $multi $always');

	if ($REMOTE && $always is $null) {
		if ($client !is $mclient) {
			local('$file');
			$file = chooseFile(\$title, \$file, \$sel, \$dir, \$multi, \$fc, $always => 1);
			if (-exists $file) {
				warn("Uploading $file");
				return uploadFile($file);
			}
			return "";
		}
		else {
			return ask("Please type a file name:");
		}
	}


	$fc = [new JFileChooser];

	if ($title !is $null) {
		[$fc setDialogTitle: $title];
	}

	if ($sel !is $null) {
		[$fc setSelectedFile: [new java.io.File: $sel]];
	}

	if ($dir !is $null) {
		[$fc setCurrentDirectory: [new java.io.File: $dir]];
	}

	if ($multi !is $null) {
		[$fc setMultiSelectionEnabled: 1];
	}

	[$fc showOpenDialog: $frame];

	if ($multi) {
		return [$fc getSelectedFiles];
	}
	else {
		$file = [$fc getSelectedFile];
		if ($file !is $null) {
			if (-exists $file) {
				return $file;
			}
			showError("$file does not exist!");
		}
	}
}

sub saveFile2 {
	local('$fc $file $sel');
	$fc = [new JFileChooser];

	if ($sel !is $null) {
		[$fc setSelectedFile: [new java.io.File: $sel]];
	}

	[$fc showSaveDialog: $frame];
	$file = [$fc getSelectedFile];
	if ($file !is $null) {
		return $file;
	}
}

sub saveFile {
	local('$fc $file');
	$fc = [new JFileChooser];
	[$fc showSaveDialog: $frame];
	$file = [$fc getSelectedFile];
	if ($file !is $null) {
		local('$ihandle $data $ohandle');
		$ihandle = openf($1);
		$ohandle = openf("> $+ $file");
		while $data (readb($ihandle, 8192)) {
			writeb($ohandle, $data);
		}
		closef($ihandle);
		closef($ohandle);
	}
}

# label_for("text", width, component)
sub label_for {
	local('$panel $label $size');
	$panel = [new JPanel];
	[$panel setLayout: [new FlowLayout: [FlowLayout LEFT]]];

	$label = [new JLabel: $1];
	
	$size = [$label getPreferredSize];
	[$label setPreferredSize: [new Dimension: $2, [$size getHeight]]];

	[$panel add: $label];
	[$panel add: $3];

	if (size(@_) >= 4) {
		[$panel add: $4];
	}

	return $panel;
}

sub center {
	local('$panel $c');
	$panel = [new JPanel];
	[$panel setLayout: [new FlowLayout: [FlowLayout CENTER]]];

	foreach $c (@_) {
		[$panel add: $c];
	}

	return $panel;
}

sub left {
	local('$panel $c');
	$panel = [new JPanel];
	[$panel setLayout: [new FlowLayout: [FlowLayout LEFT]]];

	foreach $c (@_) {
		[$panel add: $c];
	}

	return $panel;
}

sub dialog {
	local('$dialog $4');
        $dialog = [new JDialog: $frame, $1];
        [$dialog setSize: $2, $3];
        [$dialog setLayout: [new BorderLayout]];
        [$dialog setLocationRelativeTo: $frame];
	return $dialog;
}

sub window {
	local('$dialog $4');
        $dialog = [new JFrame: $1];
	[$dialog setIconImage: [ImageIO read: resource("resources/armitage-icon.gif")]];
	[$dialog setDefaultCloseOperation: [JFrame EXIT_ON_CLOSE]];
        [$dialog setSize: $2, $3];
        [$dialog setLayout: [new BorderLayout]];
	return $dialog;
}

# overlay_images(@("image.png", "image2.png", "..."))
#   constructs an image by overlaying all the specified images over eachother.
#   this function caches the result so each combination is only created once.
sub overlay_images {
	this('%cache');

	if (join(';', $1) in %cache) {
		return %cache[join(';', $1)];
	}

	local('$file $image $buffered $graphics');

        $buffered = [new BufferedImage: 1000, 776, [BufferedImage TYPE_INT_ARGB]];
	$graphics = [$buffered createGraphics];
	foreach $file ($1) {
		$image = [ImageIO read: resource($file)];
		[$graphics drawImage: $image, 0, 0, 1000, 776, $null];
	}

	$buffered = [$buffered getScaledInstance: 250 / $scale, 194 / $scale, [Image SCALE_SMOOTH]];

	%cache[join(';', $1)] = $buffered;
        return $buffered;
}

sub iconToImage {
	if ($1 isa ^ImageIcon) {
		return [$1 getImage];
	}
	else {
		local('$buffered $g');
	        $buffered = [new BufferedImage: [$1 getIconWidth], [$1 getIconHeight], [BufferedImage TYPE_INT_ARGB]];
		$g = [$buffered createGraphics];
		[$1 paintIcon: $null, $g, $2, $3];
		[$g dispose];
		return $buffered;
	}
}

sub select {
	local('$combo');
	$combo = [new JComboBox: cast($1, ^String)];
	[$combo setSelectedItem: $2];
	return $combo;
}

# buildTreeNodes(@)
sub buildTree {
	local('%nodes $entry $parent $path');

	foreach $entry ($1) {
		$parent = %nodes;
		foreach $path (split('\\/', $entry)) {
			if ($path !in $parent) {
				$parent[$path] = %();
			}
			$parent = $parent[$path];
		}
	}
	return %nodes;
}

# treeNodes($1, buildTree(@(...)))
sub treeNodes {
        local('$temp $p');

	if ($1 is $null) {
		$1 = [new DefaultMutableTreeNode: "modules"];
		[$1 setAllowsChildren: 1];
	}


	foreach $temp (sorta(keys($2))) {
		$p = [new DefaultMutableTreeNode: $temp];
		[$p setAllowsChildren: 1];

		if (size($2[$temp]) > 0) {
			treeNodes($p, $2[$temp]);
		}

		[$1 add: $p];
	}

	return $1;
}

sub wrapComponent {
	local('$panel');
	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];
	[$panel add: $1, [BorderLayout CENTER]];
	[$panel setBorder: [BorderFactory createEmptyBorder: $2, $2, $2, $2]];
	return $panel;
}

sub setLookAndFeel {
	local('$laf');
	foreach $laf ([UIManager getInstalledLookAndFeels]) {
		if ([$laf getName] eq [$preferences getProperty: "application.skin.skin", "Nimbus"]) {
			[UIManager setLookAndFeel: [$laf getClassName]];
		}
	}
}

sub thread {
	local('$thread');
	$thread = [new ArmitageThread: $1];
	[$thread start];
}

sub compareHosts {
	return [Route ipToLong: $1] <=> [Route ipToLong: $2];
}

# tells table to save any edited cells before going forward...
sub syncTable {
	if ([$1 isEditing]) {
		[[$1 getCellEditor] stopCellEditing];
	}
}

sub isWindows {
	return iff("*Windows*" iswm systemProperties()["os.name"], 1);
}

# creates a list dialog,
# $1 = title, $2 = button text, $3 = columns, $4 = rows, $5 = callback
sub quickListDialog {
	local('$dialog $panel $table $row $model $button $sorter $after $a');
	$dialog = dialog($1, $width, $height);
	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];
	
	$model = [new GenericTableModel: sublist($3, 1), $3[0], 8];
	foreach $row ($4) {
		[$model _addEntry: $row];
	}

	$table = [new JTable: $model];
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];
	$sorter = [new TableRowSorter: $model];
	[$table setRowSorter: $sorter];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];
	
	$button = [new JButton: $2];
	[$button addActionListener: lambda({
		[$callback : [$model getSelectedValueFromColumn: $table, $lead]]; 
		[$dialog setVisible: 0];
	}, \$dialog, $callback => $5, \$model, \$table, $lead => $3[0])];

	local('$south');
	$south = [new JPanel];
        [$south setLayout: [new BoxLayout: $south, [BoxLayout Y_AXIS]]];

	if ($after !is $null) {
		foreach $a ($after) {
			[$south add: $a];
		}
	}
	[$south add: center($button)];

	[$panel add: $south, [BorderLayout SOUTH]];
	[$dialog add: $panel, [BorderLayout CENTER]];
	[$dialog show];
	[$dialog setVisible: 1];
}

#
# a convienence method to return a table cell renderer that is generated in a separate sleep environment (to prevent locking issues)
# A quick sleep lesson for you: fork({ code }) runs { code } in a separate thread with a new interpreter. It's possible to return an
# object from it. In this case, the returned object is a Sleep function that when called executes with a completely unrelated context
# to the current context. It's impossible for this context to interfere with the main context. It's 1:35am. That's the best I can do.
#
sub tableRenderer {
	return wait(fork({
		return lambda({
			local('$render $v $content');
			$render = [$table getDefaultRenderer: ^String];

			$content = iff ($2 eq "PAYLOAD" || "*FILE*" iswm $2 || $2 eq "RHOST" || $2 eq "RHOSTS", "$2 \u271A", $2);
			$v = [$render getTableCellRendererComponent: $1, $content, $3, $4, $5, $6];
			[$v setToolTipText: [$model getValueAtColumn: $table, $5, "Tooltip"]];

			return $v;
		}, \$table, \$model);
	}, $table => $1, $model => $2));
}

sub gotoFile {
	return lambda({
		local('$exception');
		try {
			[[Desktop getDesktop] open: $f];
		}
		catch $exception {
			showError("Could not open $f $+ \n $+ $exception");
		}
	}, $f => $1);
}
