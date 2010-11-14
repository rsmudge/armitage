#
# File Browser (for Meterpreter)
#

import table.*;
import tree.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;
import javax.swing.filechooser.*;
import javax.swing.text.*;

import java.io.*;

global('%files %icons %paths');
%files = ohash();
%paths = ohash();
setMissPolicy(%paths, { return [new PlainDocument]; });

%icons = ohash();
setMissPolicy(%files, { return [new GenericTableModel: @("D", "Name", "Size", "Modified", "Mode"), "Name", 128]; });
setMissPolicy(%icons, {
	local('$file');
	$file = [new File: $2];
#	return [[FileSystemView getFileSystemView] getSystemIcon: $file];
});

sub parseListing {
	this('$cwd');

	local('$model');
	$model = %files[$1];

	if ($0 eq "begin") {
		[$model clear: 128];
	}
	else if ($0 eq "end") {
		[$model fireListeners];
		if ($cwd !is $null) {
			[$cwd reset];
			$cwd = $null;
		}
	}
	else if ($0 eq "update") {
		if ($2 ismatch 'Listing: (.*?)') {
			local('$path');
			($path) = matched();
			[%paths[$1] remove: 0, [%paths[$1] getLength]];
			[%paths[$1] insertString: 0, $path, $null];
		}
		else {
			local('$mode $size $type $last $name');
			($mode, $size, $type, $last, $name) = split('\s{2,}', $2);

			if ($size ismatch '\d+' && $name ne "." && $name ne "..") {
				[$model addEntry: %(Name => $name, D => $type, Size => iff($type eq "dir", "", $size), Modified => $last, Mode => $mode)];
			}
		}
	}
}

%handlers["ls"] = &parseListing;

sub createFileBrowser {
	local('$table $tree $model $panel $split $scroll1 $sorter $up $text $fsv $chooser $upload $mkdir $refresh $top');

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$model = %files[$1];
	$table = [new JTable: $model];
	[$table setShowGrid: 0];

        $sorter = [new TableRowSorter: $model];
	[$sorter toggleSortOrder: 0];
        [$table setRowSorter: $sorter];

        [$sorter setComparator: 2, {
                return long($1) <=> long($2);
        }];


	[[$table getColumn: "D"] setMaxWidth: 32];

	[[$table getColumn: "D"] setCellRenderer: lambda({
		# getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int column) 
		local('$label');

		$label = [$parent getTableCellRendererComponent: $1, $null, $3, $4, $5, $6];

		if ($2 eq "dir") {
			local('$fsv $chooser');
			$fsv = [FileSystemView getFileSystemView];
			$chooser = [$fsv getSystemIcon: [$fsv getDefaultDirectory]];
			[$label setIcon: $chooser];
		}
		else {
			[$label setIcon: $null];
		}		
	
		return $label;
	}, $parent => [$table getDefaultRenderer: ^Object], \$table)];

	# make sure subsequent columns do not have an icon associated with them...
	[[$table getColumn: "Name"] setCellRenderer: lambda({ 
		local('$label');
		$label = [$parent getTableCellRendererComponent: $1, $2, $3, $4, $5, $6];
		[$label setIcon: $null];
		return $label;
	}, $parent => [$table getDefaultRenderer: ^Object], \$table)];

	[[$table getColumn: "Size"] setCellRenderer: lambda({ 
		local('$label');

		$label = [$parent getTableCellRendererComponent: $1, $null, $3, $4, $5, $6];

		local('$size $units');
		$size = long($2);
		$units = "b";
		
		if ($2 eq "") {
			[$label setText: ""];
			return $label;
		}

		if ($size > 1024) {
			$size = long($size / 1024);
			$units = "kb";			
		}

		if ($size > 1024) {
			$size = round($size / 1024.0, 2);
			$units = "mb";
		}

		if ($size > 1024) {
			$size = round($size / 1024.0, 2);
			$units = "gb";
		}

		[$label setText: "$size $+ $units"];
		return $label;
	}, $parent => [$table getDefaultRenderer: ^Object], \$table)];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	$text = [new JTextField: %paths[$1], "", 80];
	[$text addActionListener: lambda({
		m_cmd($sid, "cd \"" . strrep([[$1 getSource] getText], "\\", "\\\\") . "\"");
		m_cmd($sid, "ls");
	}, $sid => $1)];

	[$table addMouseListener: lambda({
		if ($0 eq 'mouseClicked' && [$1 getClickCount] >= 2) {
			local('$model $sel');
			$model = %files[$sid];
			$sel = [$model getSelectedValue: $table];
			m_cmd($sid, "cd \" $+ $sel $+ \"");
			m_cmd($sid, "ls");
		}
		else if ([$1 isPopupTrigger]) {
			local('$popup $model');
			$popup = [new JPopupMenu];
			$model = %files[$sid];
			buildFileBrowserMenu($popup, [$model getSelectedValues: $table], convertAll([$model getRows]), \$sid);
			[$popup show: [$1 getSource], [$1 getX], [$1 getY]];
		}
	}, $sid => $1, \$table)];
	
	$fsv = [FileSystemView getFileSystemView];
	$chooser = [$fsv getSystemIcon: [$fsv getDefaultDirectory]];
	
	$up = [new JButton: $chooser];
	[$up setBorder: [BorderFactory createEmptyBorder: 2, 2, 2, 8]];
	[$up setOpaque: 0];
	[$up setContentAreaFilled: 0];
	[$up setToolTipText: "Go up one directory"];

	[$up addActionListener: lambda({ 
		m_cmd($sid, "cd ..");
		m_cmd($sid, "ls");
	}, $sid => $1)];

	# setup the whatever it's called...

	$upload = [new JButton: "Upload..."];
	[$upload addActionListener: lambda({
		local('$file');
		$file = chooseFile();
		if ($file !is $null) {
			m_cmd($sid, "upload $file " . getFileName($file));
			m_cmd($sid, "ls");
		}
		# refresh?!?
	}, $sid => $1)];

	$mkdir = [new JButton: "Make Directory"];
	[$mkdir addActionListener: lambda({
		local('$name');
		$name = ask("Directory name:");
		if ($name !is $null) {
			m_cmd($sid, "mkdir $name");
			m_cmd($sid, "ls");
		}
		# refresh?
	}, $sid => $1)];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		m_cmd($sid, "ls");
	}, $sid => $1)];

	# do the overall layout...

	$top = [new JPanel];
	[$top setBorder: [BorderFactory createEmptyBorder: 3, 3, 3, 3]];
	[$top setLayout: [new BorderLayout]];
	[$top add: $text, [BorderLayout CENTER]];
	[$top add: $up, [BorderLayout WEST]];

	[$panel add: $top, [BorderLayout NORTH]];
	[$panel add: center($upload, $mkdir, $refresh), [BorderLayout SOUTH]];

	[$frame addTab: "Files $1", $panel, $null];

	m_cmd($1, "ls");
}

sub buildFileBrowserMenu {
	# ($popup, [$model getSelectedValue: $table], @rows);
	
	# turn @rows into %(file => type)
	local('%types');
	map(lambda({ %types[$1["Name"]] = $1["D"]; }, \%types), $3);

	item($1, "Download", 'D', lambda({ 
		local('$f');
		foreach $f ($file) {
			if (%types[$f] eq "dir") {
				m_cmd($sid, "download -r \" $+ $f $+ \""); 
			}
			else {
				m_cmd($sid, "download \" $+ $f $+ \""); 
			}
		}
	}, $file => $2, \$sid, \%types));

	separator($1);

	item($1, "Delete", 'l', lambda({ 
		local('$f');
		foreach $f ($file) {
			if (%types[$f] eq "dir") {
				m_cmd($sid, "rmdir \" $+ $f $+ \""); 
			}
			else {
				m_cmd($sid, "rm \" $+ $f $+ \""); 
			}
		}
		m_cmd($sid, "ls");
	}, $file => $2, \$sid, \%types));

	item($1, "Rename", 'R', lambda({ 
		local('$name $f');
		foreach $f ($file) {
			$name = ask("New name for $+ $f $+ ?");
			if ($name !is $null) {
				m_cmd($sid, "rename \" $+ $f $+ \" \" $+ $name $+ \""); 
			}
		}
		m_cmd($sid, "ls");
	}, $file => $2, \$sid));
}
 
# Buttons:
# [upload...] [make directory] 
#
