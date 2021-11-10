#
# Screenshot viewer... whee?!?
#
import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.imageio.*;
import java.io.File;

import ui.*;

import armitage.*;

global('%screenshots %webcams %refreshcmd');
%screenshots = ohash();
%webcams = ohash();

sub image_viewer {
	local('$panel $viewer $buttons $refresh $watch');

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

		$viewer = [new ZoomableImage];
		[$panel add: [new JScrollPane: $viewer], [BorderLayout CENTER]];

		$buttons = [new JPanel];
		[$buttons setLayout: [new FlowLayout: [FlowLayout CENTER]]];
			$refresh = [new JButton: "Refresh"];
			[$refresh addActionListener: lambda({
				m_cmd($sid, %refreshcmd[$title][$sid]);
			}, $sid => $2, \$command, \$title)];
			[$buttons add: $refresh];

			$watch = [new JButton: "Watch (10s)"];
			[$watch addActionListener: lambda({
				local('$timer');
				$timer = [new SimpleTimer: 10000];
				[$timer setRunnable: lambda({
					if ($sid !in $container) {
						[$timer stop];
					}
					else {
						m_cmd($sid, %refreshcmd[$title][$sid]);
					}
				}, \$sid, \$timer, \$container, \$title)];
			}, $sid => $2, \$container, \$title)];
			[$buttons add: $watch];
		[$panel add: $buttons, [BorderLayout SOUTH]];
	
	[$frame addTab: "$title $2", $panel, lambda({ $container[$key] = $null; size($container); }, $key => $2, \$container), "$title " . sessionToHost($2)];
	return $viewer;
}

sub update_viewer {
	if ($0 eq "execute") {
		%refreshcmd[$title][$1] = $2;
	}
	else if ($0 eq "update" && "*Operation failed*" iswm $2) {
		showError($2);
	}
	else if ($0 eq "update" && $2 ismatch "$type saved to: (.*?)") {
		local('$file');
		($file) = matched();

		[lambda({
			local('$image $panel');

			# we're collaborating, so download the file please...
			if ($client !is $mclient) {
				downloadFile($file, $null, $this);
				yield;
				$file = getFileProper(cwd(), $1);
			}

			logFile($file, sessionToHost($sid), $type);
			$image = [ImageIO read: [new File: $file]];

			fire_event_async("user_" . lc(strrep($type, " ", "_")), $sid, $file);

			dispatchEvent(lambda({
				[$container[$id] setIcon: [new ImageIcon: $image]];
			}, \$container, \$image, $id => $sid));

			if (-isFile $file && "*.jpeg" iswm $file) { 
				deleteOnExit($file);
			}
		}, \$file, $sid => $1, \$type, \$title, \$container)];
	}
}

setMissPolicy(%screenshots, lambda(&image_viewer, $title => "Screenshot", $container => %screenshots));
setMissPolicy(%webcams, lambda(&image_viewer, $title => "Webcam", $container => %webcams));

%handlers["screenshot"] = lambda(&update_viewer, $type => "Screenshot", $title => "Screenshot", $container => %screenshots);
%handlers["webcam_snap"] = lambda(&update_viewer, $type => "Webcam shot", $title => "Webcam", $container => %webcams);

sub createScreenshotViewer {
	return lambda({
		m_cmd($sid, "screenshot -v false");
	}, $sid => $1);
}

sub createWebcamViewer {
	return lambda({
		m_cmd_callback($sid, "webcam_list", {
			if ($0 eq "end") {
				local('$cams $cam');
				$cams = map({ return %(Camera => $1); }, split("\n", ["$2" trim]));

				# get rid of non-camera entries please
				foreach $cam ($cams) {
					if ($cam['Camera'] !ismatch '\d+: .*') {
						remove();
					}
				}

				# no camera... do nothing.
				if (size($cams) == 0) {
					showError("Host does not have a camera");
					return;
				}

				quickListDialog("Cameras", "Take Picture", @("Camera", "Camera"), $cams, $width => 320, $height => 200, lambda({
					if ($1 !is $null) {
						local('$index');
						($index) = split(': ', $1);
						m_cmd($sid, "webcam_snap -i $index -v false");
					}
				}, $sid => $1));
			}
		});
	}, $sid => $1);
}
