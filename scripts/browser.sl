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

global('%files %icons %paths %attribs');
%files = ohash();
%paths = ohash();
%attribs = ohasha();
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
		if ("*Operation failed*" iswm $2) {
			showError("$2 $+ \n\nMaybe you don't have permission to access \nthis folder? Press the directory up button.");
		}
		else if ($2 ismatch 'Listing: (.*?)' || $2 ismatch 'No entries exist in (.*?)') {
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

# setupSizeRenderer($table, "columnname")
sub setupSizeRenderer {
	[[$1 getColumn: $2] setCellRenderer: safeColumnRenderer({ 
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
	}, $parent => [$1 getDefaultRenderer: ^Object], $table => $1)];
}

sub safeColumnRenderer {
	# this function creates a new sleep thread (a separate script environment for locking purposes)
	# and sanitizes the specified function through it. This returned function is now safe for use
	# in a swing thread and will not cause deadlock.
	return wait(fork({
		return lambda($function, \$table, \$parent);
	}, \$table, \$parent, $function => $1));
}

sub createFileBrowser {
	local('$table $tree $model $panel $split $scroll1 $sorter $up $text $fsv $chooser $upload $mkdir $refresh $top $setcwd');

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$model = %files[$1];
	$table = [new JTable: $model];
	[$table setShowGrid: 0];

        $sorter = [new TableRowSorter: $model];
	[$sorter toggleSortOrder: 0];
        [$table setRowSorter: $sorter];

	# file size column
        [$sorter setComparator: 2, {
                return long($1) <=> long($2);
        }];

	# last modified column
	[$sorter setComparator: 3, {
		return convertDate($1) <=> convertDate($2);
	}];

	[[$table getColumn: "D"] setMaxWidth: 32];

	[[$table getColumn: "D"] setCellRenderer: safeColumnRenderer({
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
	[[$table getColumn: "Name"] setCellRenderer: safeColumnRenderer({
		local('$label');
		$label = [$parent getTableCellRendererComponent: $1, $2, $3, $4, $5, $6];
		[$label setIcon: $null];
		return $label;
	}, $parent => [$table getDefaultRenderer: ^Object], \$table)];

	setupSizeRenderer($table, "Size");

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	$text = [new JTextField: %paths[$1], "", 80];
	[$text addActionListener: lambda({
		local('$dir');
		$dir = [[$1 getSource] getText];
		m_cmd($sid, "cd ' $+ $dir $+ '");
		m_cmd($sid, "pwd");
		m_cmd($sid, "ls");
		[[$1 getSource] setText: ""];
	}, $sid => $1)];

	# this function should be called before every browser action to keep things in sync.
	$setcwd = lambda({
		m_cmd($sid, "cd '" . [$text getText] . "'");
	}, \$text, $sid => $1, $platform => $2);	

	[$table addMouseListener: lambda({
		if ($0 eq 'mouseClicked' && [$1 getClickCount] >= 2) {
			local('$model $sel');
			$model = %files[$sid];
			$sel = [$model getSelectedValue: $table];

			if ("*Windows*" iswm sessionToOS($sid)) {
				m_cmd($sid, "cd '" . [$text getText] . "\\ $+ $sel $+ '");
			}
			else {
				[$setcwd];
				m_cmd($sid, "cd ' $+ $sel $+ '");
			}

			m_cmd($sid, "pwd");
			m_cmd($sid, "ls");
			[$1 consume];
		}
		else if ([$1 isPopupTrigger]) {
			local('$popup $model');
			$popup = [new JPopupMenu];
			$model = %files[$sid];
			buildFileBrowserMenu($popup, [$model getSelectedValues: $table], convertAll([$model getRows]), \$sid, \$setcwd, \$text);
			[$popup show: [$1 getSource], [$1 getX], [$1 getY]];
			[$1 consume];
		}
	}, $sid => $1, \$table, \$setcwd, \$text)];
	
	$fsv = [FileSystemView getFileSystemView];
	$chooser = [$fsv getSystemIcon: [$fsv getDefaultDirectory]];
	
	$up = [new JButton: $chooser];
	[$up setPressedIcon: 
		[new ImageIcon: iconToImage($chooser, 2, 2)]
	];
	[$up setBorder: [BorderFactory createEmptyBorder: 2, 2, 2, 8]];
	[$up setOpaque: 0];
	[$up setContentAreaFilled: 0];
	[$up setToolTipText: "Go up one directory"];

	[$up addActionListener: lambda({ 
		this('$last');
		if ((ticks() - $last) < 500) {
			warn("Dropping cd .. -- too fast");
			$last = ticks();
			return;
		}
		$last = ticks();

		if ("*Windows*" iswm sessionToOS($sid)) {
			m_cmd($sid, "cd '" . [$text getText] . "\\..'");
		}
		else {
			[$setcwd];
			m_cmd($sid, "cd ..");
		}
		m_cmd($sid, "pwd");
		m_cmd($sid, "ls");
	}, $sid => $1, \$setcwd, \$text)];

	# setup the whatever it's called...

	$upload = [new JButton: "Upload..."];
	[$upload addActionListener: lambda({
		local('$file $name');
		$file = chooseFile($always => iff($client !is $mclient));
		$name = getFileName($file);
		if ($file !is $null) {
			[$setcwd];
			if ($client !is $mclient) {
				$file = uploadFile($file);
			}
			m_cmd($sid, "upload \" $+ $file $+ \" \" $+ $name $+ \"");
		}
		# refresh?!?
	}, $sid => $1, \$setcwd)];

	$mkdir = [new JButton: "Make Directory"];
	[$mkdir addActionListener: lambda({
		local('$name');
		$name = ask("Directory name:");
		if ($name !is $null) {
			[$setcwd];
			m_cmd($sid, "mkdir \" $+ $name $+ \"");
			m_cmd($sid, "ls");
		}
		# refresh?
	}, $sid => $1, \$setcwd)];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		[$setcwd];
		m_cmd($sid, "ls");
	}, $sid => $1, \$setcwd)];

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

sub convertDate {
	if ($1 ismatch '\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d .*') {
		return parseDate('yyyy-MM-dd HH:mm:ss Z', $1);
	}
	else {
		return parseDate("EEE MMM dd HH:mm:ss Z yyyy", $1);
	}
}

# automagically store timestomp attributes...
%handlers["timestomp"] = {
	if ($0 eq "update" && $2 ismatch '([MACE].*?)\s*: (.*)') {
		local('$type $value $d');
		($type, $value) = matched();
		%attribs[["$type" trim]] = formatDate(convertDate($value), 'MM/dd/yyyy HH:mm:ss');
	}
};

sub buildFileBrowserMenu {
	# ($popup, [$model getSelectedValue: $table], @rows);
	
	# turn @rows into %(file => type)
	local('%types');
	map(lambda({ %types[$1["Name"]] = $1["D"]; }, \%types), $3);

	item($1, "Download", 'D', lambda({ 
		local('$f $dir @temp $tdir');
		@temp = split('\\\\', [$text getText]);
		$dir = downloadDirectory(sessionToHost($sid), join("/", @temp));

		foreach $f ($file) {
			[$setcwd];
			if (%types[$f] eq "dir") {
				$tdir = downloadDirectory(sessionToHost($sid), join("/", @temp), $f);
				m_cmd($sid, "download -r \" $+ $f $+ \" \" $+ $tdir $+ \""); 
			}
			else {
				m_cmd($sid, "download \" $+ $f $+ \" \" $+ $dir $+ \""); 
			}
		}
		showError("Downloading:\n\n" . join("\n", $file) . "\n\nUse View -> Downloads to see files");
		elog("downloaded " . join(", ", $file) . " from " . [$text getText] . " on " . sessionToHost($sid));
	}, $file => $2, \$sid, \%types, \$setcwd, \$text));

	item($1, "Execute", 'E', lambda({ 
		local('$f $args');
		[$setcwd];

		$args = ask("Arguments?");

		foreach $f ($file) {
			if ($args eq "") {
				m_cmd($sid, "execute -t -f \" $+ $f $+ \" -k"); 
			}
			else {
				$args = strrep($args, '\\', '\\\\');
				m_cmd($sid, "execute -t -f \" $+ $f $+ \" -k -a \" $+ $args $+ \""); 
			}
		}
	}, $file => $2, \$sid, \$setcwd));

	separator($1);

	# use timestomp to make sure the date/time stamp is the same. :)
	local('$t $key $value');
	$t = menu($1, "Timestomp", 'T');
	item($t, "Get MACE values", 'G', lambda({
		[$setcwd];
		m_cmd($sid, "timestomp \" $+ $f $+ \" -v");
	}, \$sid, $f => $2[0], \$setcwd));

	if (size(%attribs) > 0) {
		separator($t);

		foreach $key => $value (%attribs) {
			item($t, "Set $key to $value", $null, lambda({
				local('%switches $s $f');
				[$setcwd];
				foreach $f ($files) {
					%switches = %(Modified => '-m', Accessed => '-a', Created => '-c');
					%switches["Entry Modified"] = '-e';
					$s = %switches[$key];
					m_cmd($sid, "timestomp \" $+ $f $+ \" $s \" $+ $value $+ \"");
				}
				m_cmd($sid, "ls");
			}, $files => $2, \$sid, $key => "$key", $value => "$value", \$setcwd));
		}

		separator($t);
		item($t, "Set MACE values", 'S', lambda({
			local('$f %switches $s $cmd $key $value');
			%switches = %(Modified => '-m', Accessed => '-a', Created => '-c');
			%switches["Entry Modified"] = '-e';

			[$setcwd];

			foreach $f ($files) {
				$cmd = "timestomp \" $+ $f $+ \"";

				foreach $key => $value (%attribs) {
					$s = %switches[$key];
					$cmd = "$cmd $s \" $+ $value $+ \"";
				}

				m_cmd($sid, $cmd);
			}

			m_cmd($sid, "ls"); 
		}, $files => $2, \$sid, \$setcwd));
	}
	
	item($1, "Delete", 'l', lambda({ 
		local('$f');
		[$setcwd];
		foreach $f ($file) {
			if (%types[$f] eq "dir") {
				m_cmd($sid, "rmdir \" $+ $f $+ \""); 
			}
			else {
				m_cmd($sid, "rm \" $+ $f $+ \""); 
			}
		}
		m_cmd($sid, "ls");
	}, $file => $2, \$sid, \%types, \$setcwd));
}
 
# Buttons:
# [upload...] [make directory] 
#
