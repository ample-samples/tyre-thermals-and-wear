angular.module("beamng.apps")
    .directive("tyreWearThermals", ["CanvasShortcuts", function (CanvasShortcuts) {
        return {
            template: '<canvas width="220"></canvas>',
            replace: true,
            restrict: "EA",
            link: function (scope, element, attrs) {
                var streamsList = ["TyreWearThermals"];
                StreamsManager.add(streamsList);
                scope.$on("$destroy", function () {
                    StreamsManager.remove(streamsList);
                });
                var c = element[0], ctx = c.getContext("2d");
                scope.$on('app:resized', function (event, data) {
                    c.width = data.width
                    c.height = data.height
                });
                scope.$on("streamsUpdate", function (event, streams) {
                    // From: https://stackoverflow.com/a/3368118
                    var wheelCount = streams.TyreWearThermals.data.length;
                    function roundRect(
                        ctx,
                        x,
                        y,
                        width,
                        height,
                        radius = 5,
                        fill = false,
                        stroke = true
                    ) {
                        if (typeof radius === 'number') {
                            radius = { tl: radius, tr: radius, br: radius, bl: radius };
                        } else {
                            radius = { ...{ tl: 0, tr: 0, br: 0, bl: 0 }, ...radius };
                        }
                        ctx.beginPath();
                        ctx.moveTo(x + radius.tl, y);
                        ctx.lineTo(x + width - radius.tr, y);
                        ctx.quadraticCurveTo(x + width, y, x + width, y + radius.tr);
                        ctx.lineTo(x + width, y + height - radius.br);
                        ctx.quadraticCurveTo(x + width, y + height, x + width - radius.br, y + height);
                        ctx.lineTo(x + radius.bl, y + height);
                        ctx.quadraticCurveTo(x, y + height, x, y + height - radius.bl);
                        ctx.lineTo(x, y + radius.tl);
                        ctx.quadraticCurveTo(x, y, x + radius.tl, y);
                        ctx.closePath();
                        if (fill) {
                            ctx.fill();
                        }
                        if (stroke) {
                            ctx.stroke();
                        }
                    }

                    function drawWheelData(name, temps, working_temp, condition, camber, tyreNumber) {
                        if (Object.keys(temps).length == 0) {
                            temps = Array(4).fill(0)
                        }

                        if (condition == undefined) {
                            condition = [100, 100, 100]
                        }

                        ctx.textAlign = 'center';

                        var right = 0;
                        var back = 0;

                        var w = c.width / 3.5;
                        var h = c.height / 3.5;
                        h = h / (wheelCount / 4)
                        if (tyreNumber % 2 == 1) {
                            right = 1
                        }
                        back = Math.floor(tyreNumber / 2)

                        if (name[name.length-1] == "R") {
                            // give correct L/R position for some wheels
                            right = 1
                        } else if (name[name.length-1] == "L") {
                            right = 0
                        }

                        if (name == "FR" || name == "RR") {
                            right = 1;
                        } else if (name == "FL" || name == "RL") {
                            // overwrite incorrect front positions given
                            // by previous checks
                            right = 0;
                        }

                        if (name == "RR2") {
                            right = 1
                        } else if (name =="RL2") {
                            right = 0
                        }

                        if (name == "RR" || name == "RL") {
                            back = 1;
                        } else if (name == "FR" || name == "FL") {
                            back = 0;
                        } else if (name == "RL2" || name == "RR2") {
                            back = 2;
                        } 

                        var x = w * 0.5 + ((w * 1.5) * right);
                        var y = (h * 0.5 + ((h * 1.5) * back)) + h * 0.1;
                        var cx = x + w * 0.5;
                        var cy = y + h * 0.5;

                        h = h * 0.8;

                        // Draw info text
                        ctx.fillStyle = "#ffffffff";
                        ctx.font = 'bold 18pt "Lucida Console", Monaco, monospace';
                        ctx.fillText("" + Math.ceil(condition) + "%", cx, y - 8); 

                        var t = condition / 100;

                        var lowHue = 0;
                        var highHue = 248;

                        for (let i = 0; i < 3; i++) {

                            var crad = 8.0;
                            var radius = { tl: 0, tr: 0, br: 0, bl: 0 };
                            if (i == 0) {
                                radius = { tl: crad, tr: 0, br: 0, bl: crad };
                            } else if (i == 2) {
                                radius = { tl: 0, tr: crad, br: crad, bl: 0 };
                            }

                            const sectionWidth = (w / 3.0 - 1.5) / 3 * 3
                            const sectionXOffset = sectionWidth * i + 2
                            ctx.lineWidth = "0";
                            ctx.fillStyle = "rgba(0,0,0,0.45)";
                            ctx.beginPath();
                            ctx.rect(x + sectionXOffset, y + 1, sectionWidth, h - 2);
                            ctx.fill();
                            // Draw temps and condition if tyre is not worn completely
                            if (condition > 1) {
                                // Skin
                                const tempTSkin = 1.0 - Math.min(Math.max(temps[i] / working_temp - 0.5, 0), 1);
                                const hueSkin = lowHue + (highHue - lowHue) * tempTSkin;
                                const ftSkin = 1.0 - (condition / 100);
                                ctx.fillStyle = "hsla(" + hueSkin + ",82%,56%,1)";
                                ctx.beginPath();
                                ctx.rect(x + sectionXOffset, y + h * ftSkin + 1, sectionWidth, h - h * ftSkin - 2);
                                ctx.fill();

                                // Carcass
                                const tempTCarcass = 1.0 - Math.min(Math.max((temps[i+3]) / working_temp - 0.5, 0), 1);
                                const hueCarcass = lowHue + (highHue - lowHue) * tempTCarcass;
                                const ftCarcass = (1.0 - (condition / 100)) / 2;
                                ctx.fillStyle = "hsla(" + hueCarcass + ",82%,56%,1)";
                                ctx.beginPath();
                                ctx.rect(x + sectionXOffset, y + h / 2 * ftCarcass, sectionWidth, h /2 - h * ftCarcass);
                                ctx.fill();
                            }
                            ctx.lineWidth = "3";
                            ctx.strokeStyle = "rgba(0,0,0,1)";
                            roundRect(ctx, x + sectionXOffset, y, sectionWidth, h, radius, false);

                            // Info text
                            ctx.fillStyle = "#ffffffff";
                            var font_size = Math.max(Math.min(w / 20.0 * 3.0, 16.0), 4.0);
                            ctx.font = 'bold ' + font_size + 'pt "Lucida Console", Monaco, monospace';
                            ctx.fillText("" + Math.floor(temps[i+3]), x + (w / 3.0 * i) + 2 + (w / 3.0 - 8) / 2.0, y + h + 22);

                            // camber
                            ctx.fillStyle = "rgba(255,50,50,0.85)";
                            ctx.beginPath();
                            ctx.moveTo(x + w * 0.5 + w * (camber * 0.2 * 0.5), y - 2);
                            ctx.lineTo(x + w * 0.5 + w * (camber * 0.2 * 0.5) - 6, y - 8);
                            ctx.lineTo(x + w * 0.5 + w * (camber * 0.2 * 0.5) + 6, y - 8);
                            ctx.fill();

                            ctx.beginPath();
                            ctx.moveTo(x + w * 0.5 + w * (camber * 0.2 * 0.5), y + h + 2);
                            ctx.lineTo(x + w * 0.5 + w * (camber * 0.2 * 0.5) - 6, y + h + 8);
                            ctx.lineTo(x + w * 0.5 + w * (camber * 0.2 * 0.5) + 6, y + h + 8);
                            ctx.fill();
                        }

                        // Draw core temp
                        var coreTempT = 1.0 - Math.min(Math.max(temps[6] / working_temp - 0.5, 0), 1);
                        var coreHue = lowHue + (highHue - lowHue) * coreTempT;
                        if (t < 0.1) {
                            coreTempIsDisplayed = 0;
                            ctx.fillStyle = "rgba(0,0,0,0.45)";
                        } else {
                            ctx.fillStyle = "hsla(" + coreHue + ",82%,56%,1)";
                            coreTempIsDisplayed = 1;
                        }
                        if (right) {
                            roundRect(ctx, cx - w / 12.0 - w / 1.75, y + h * 0.2, w / 6, h * 0.6, 3.0, true);
                        } else {
                            roundRect(ctx, cx - w / 12.0 + w / 1.75, y + h * 0.2, w / 6, h * 0.6, 3.0, true);
                        }
                    }

                    var dataStream = streams.TyreWearThermals;
                    ctx.setTransform(1, 0, 0, 1, 0, 0); // No scaling, no skewing, no translation
                    ctx.clearRect(0, 0, c.width, c.height);

                    ctx.textAlign = 'center';

                    for (let i = 0; i < dataStream.data.length; i++) {
                        drawWheelData(
                            dataStream.data[i].name,
                            dataStream.data[i].temp,
                            dataStream.data[i].working_temp,
                            dataStream.data[i].condition,
                            dataStream.data[i].camber,
                            i
                        );
                    }
                });
            }
        }
    }])
