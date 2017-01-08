import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
	id: "entryPage"
	property var parentEntry
	property int current

	property var chapter

	property int prev: current < 0 ? -1 : current - 1
	property int next: (current + 1) < parentEntry.items.length ? current + 1 : -1
	property var partModel: chapter != undefined && chapter.items != undefined ? chapter.items : []

	signal gotoSibling (int number)
	signal markRead (bool force)
	signal markLast ()

	allowedOrientations: Orientation.Portrait | Orientation.Landscape

	// TODO: make sure to cache them ALL (and save afterwards (if any fetching was done))
	SilicaListView {
		id: "entryView"
		anchors.fill: parent

		header: Column {
			width: parent.width
			height: header.height + Theme.paddingLarge
			PageHeader {
				id: "header"
				title: parentEntry.label + ": " + "Chapter" + " " + (chapter != undefined && chapter.label != undefined ? chapter.label : ( parentEntry.items[current].label != undefined ? parentEntry.items[current].label : parentEntry.items[current].id ) )
			}

			BusyIndicator {
				running: true
				size: BusyIndicatorSize.Large
				visible: entryView.count == 0
			}
		}

		model: partModel

		delegate: FollowMeImage {
			id: "followMeImage"

			property var part: partModel[index]

			width: parent.width
			parentLocator: chapter.locator
			partIndex: index
			partId: part.id
			file: part.file
			absoluteFile: part.absoluteFile != undefined ? part.absoluteFile : ''

			onImageError: {
				console.log("image has error, redownloading it...");
				app.downloadQueue.immediate({
					locator: parentLocator.concat([{id: part.id, file: part.file, label: part.label}]),
					remoteFile: entryPage.chapter.items[partIndex]['remoteFile'],
					doneHandler: function (success, item, filename, saveEntry){
						if (!success) {
							//followMeImage.imageSource = item['remoteFile'];
							return [];
						}
						if (success && item['chapter'] != undefined && item['pageIndex'] != undefined && item['chapter'].items[item['pageIndex']] != undefined && item['chapter'].items[item['pageIndex']]['absoluteFile'] != filename) {
							item['chapter'].items[item['pageIndex']].absoluteFile = filename;
							followMeImage.imageSource = item['chapter'].items[item['pageIndex']].absoluteFile;
							saveEntry.locator = parentLocator;
							saveEntry.save(item['chapter']);
							console.log('saving entry after download (filename: ' + filename + ')');
						}
						return [];
					}
				},
				function (){
					console.log('starting download after error');
				});
			}

			menu: ContextMenu {
				MenuItem {
					text: "Refresh"
					onClicked: {
						app.downloadQueue.immediate({
							locator: parentLocator.concat([{id: part.id, file: part.file, label: part.label}]),
							remoteFile: entryPage.chapter.items[partIndex]['remoteFile'],
							redownload: true,
							doneHandler: function (success, item, filename, saveEntry){
								if (!success) {
									//followMeImage.imageSource = item['remoteFile'];
									return [];
								}
								if (success && item['chapter'] != undefined && item['pageIndex'] != undefined && item['chapter'].items[item['pageIndex']] != undefined && item['chapter'].items[item['pageIndex']]['absoluteFile'] != filename) {
									item['chapter'].items[item['pageIndex']].absoluteFile = filename;
									followMeImage.imageSource = item['chapter'].items[item['pageIndex']].absoluteFile;
									saveEntry.locator = parentLocator;
									saveEntry.save(item['chapter']);
									console.log('saving entry after download (filename: ' + filename + ')');
								}
								return [];
							}
						},
						function (){
							console.log('starting redownload');
						});
					}
				}
			}
		}

	        VerticalScrollDecorator {}

		PullDownMenu {
			visible: prev >= 0 || next > 0
			MenuItem {
				visible: parentEntry.items.length > 1
				text: qsTr("Jump To")
				onClicked: {
					var dialog = pageStack.push(Qt.resolvedUrl("SliderDialog.qml"), {
						title: qsTr("Jump to chapter"),
						number: entryPage.current + 1,
						unit: qsTr("chapter"),
						minimum: 1,
						maximum: entryPage.parentEntry.items.length
					});
					dialog.accepted.connect(function (){
						gotoSibling(dialog.number - 1);
					});
				}
			}
			MenuItem {
				visible: next > 0
				text: qsTr("Next")
				onClicked: gotoSibling(next);
			}
			MenuItem {
				visible: prev >= 0
				text: qsTr("Previous")
				onClicked: gotoSibling(prev);
			}
		}

		PushUpMenu {
			visible: next > 0
			MenuItem {
				text: qsTr("Next")
				onClicked: gotoSibling(next);
			}
		}
	}

	PySaveEntry {
		id: "saveChapter"
		base: app.dataPath
		entry: entryPage.chapter

		onFinished: {
			console.log('saving chapter: ' + (success ? "ok" : "nok"));
			app.dirtyList = true;
		}
	}

	PySaveEntry {
		id: "saveEntry"
		base: app.dataPath
		entry: entryPage.parentEntry

		onFinished: {
			console.log('saving entry: ' + (success ? "ok" : "nok"));
			app.dirtyList = true;
		}
	}

	PyLoadEntry {
		id: "loadChapter"
		base: app.dataPath
		locator: parentEntry.locator.concat([{id: parentEntry.items[current].id, file: parentEntry.items[current].file, label: parentEntry.items[current].label}])
		autostart: true

		onFinished: {
			if (success) {
				// fix label before saving parent
				if (entry.label != undefined) {
					parentEntry.items[current].label = entry.label;
				}
				markLast();
				chapter = entry;
				entryView.model = partModel;
				console.log("saving to chapter: " + entryPage.current);
				// mark it as read
				markRead(false);
				return ;
			}
			// fetch them online (not from dir)
			console.log('downloading chapter');
			// make a chapter start
			if (chapter == undefined) {
				chapter = ({id: parentEntry.items[current].id, file: parentEntry.items[current].file, label: parentEntry.items[current].label, items: [], last: -1, read: false});
			}
			// TODO: when it's done, i need to do the same stuff if it were successfull in loading...
			app.downloadQueue.immediate({
				locator: loadChapter.locator,
				depth: 1,
				sort: true,
				entry: chapter
			});
		}
	}

	onMarkRead: {
		// no need to save if already read
		if (chapter.read != undefined && chapter.read && !force) {
			return ;
		}
		// mark chapter read
		chapter.read = true;
		saveChapter.activate();
	}

	onMarkLast: {
		// no need to save parentEntry if this was the last one
		if (parentEntry.last != undefined && parentEntry.last == parentEntry.items[current].id) {
			return ;
		}
		// save last entry
		parentEntry.last = parentEntry.items[current].id;
		saveEntry.activate();
	}

	onGotoSibling: {
		console.log('gotoSibling(' + number + '): ' + entryPage.parentEntry.items[number].id);
		entryView.model = [];
		entryPage.current = number;
		entryView.model = partModel;
		loadChapter.activate();
	}
}
