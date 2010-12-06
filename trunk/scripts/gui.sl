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

sub showError {
	if ([SwingUtilities isEventDispatchThread]) {
		[JOptionPane showMessageDialog: $frame, $1];
	}
	else {
		[SwingUtilities invokeLater: lambda({
			[JOptionPane showMessageDialog: $frame, $message];
		}, $message => $1)];
	}
}

sub ask {
	return [JOptionPane showInputDialog: $1];
}

# askYesNo("title", "text")
sub askYesNo {
	return [JOptionPane showConfirmDialog: $null, $1, $2, [JOptionPane YES_NO_OPTION]];
}

sub chooseFile {
	local('$fc $file $title $sel $dir');

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

	[$fc showOpenDialog: $frame];
	$file = [$fc getSelectedFile];
	if ($file !is $null) {
		if (-exists $file) {
			return $file;
		}
		showError("$file does not exist!");
	}
}

sub saveFile2 {
	local('$fc $file');
	$fc = [new JFileChooser];
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

	$buffered = [$buffered getScaledInstance: 250, 194, [Image SCALE_SMOOTH]];

	%cache[join(';', $1)] = $buffered;
        return $buffered;
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
